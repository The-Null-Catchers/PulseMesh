import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { RealtimeEvent } from "@pulsemesh/realtime";
import { pool, withTransaction } from "../db/index.js";
import { AppError } from "../errors.js";
import {
  canAccessChannel,
  canAccessConversation,
  hasWorkspacePermission,
} from "../authorization/service.js";
import { publishRealtime } from "../realtime/bus.js";
import { recordAudit } from "../audit/service.js";

type MessageContext = {
  id: string;
  sender_user_id: string;
  channel_id: string | null;
  conversation_id: string | null;
  workspace_id: string | null;
  encryption_version: string | null;
  body: string;
};

async function messageAndRoom(
  messageId: string,
): Promise<MessageContext | null> {
  const result = await pool.query<MessageContext>(
    `SELECT
      m.id,
      m.sender_user_id,
      m.channel_id,
      m.conversation_id,
      c.workspace_id,
      m.encryption_version,
      m.body
     FROM messages m
     LEFT JOIN channels c ON c.id=m.channel_id
     WHERE m.id=$1 AND m.deleted_at IS NULL`,
    [messageId],
  );
  return result.rows[0] ?? null;
}

function roomFor(message: {
  channel_id: string | null;
  conversation_id: string | null;
}) {
  if (message.channel_id) return "channel:" + message.channel_id;
  if (message.conversation_id) {
    return "conversation:" + message.conversation_id;
  }
  throw new Error("Message has no destination");
}

async function assertMessageAccess(
  userId: string,
  message: {
    channel_id: string | null;
    conversation_id: string | null;
  },
) {
  if (
    message.channel_id &&
    !(await canAccessChannel(userId, message.channel_id))
  ) {
    throw new AppError(403, "MESSAGE_ACCESS_DENIED", "Message access denied");
  }
  if (
    message.conversation_id &&
    !(await canAccessConversation(userId, message.conversation_id))
  ) {
    throw new AppError(403, "MESSAGE_ACCESS_DENIED", "Message access denied");
  }
}

export async function messageMutationRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.patch(
    "/messages/:messageId",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          body: z.string().trim().min(1).max(20_000),
        })
        .parse(request.body);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const existing = await messageAndRoom(params.messageId);
      if (!existing) {
        throw new AppError(404, "MESSAGE_NOT_FOUND", "Message not found");
      }
      await assertMessageAccess(userId, existing);
      if (existing.encryption_version !== null) {
        throw new AppError(
          409,
          "E2EE_MESSAGE_EDIT_UNSUPPORTED",
          "Encrypted messages are immutable in the initial E2EE release",
        );
      }
      if (existing.sender_user_id !== userId) {
        throw new AppError(
          403,
          "MESSAGE_EDIT_DENIED",
          "Only the sender can edit this message",
        );
      }

      const editedAt = await withTransaction(async (client) => {
        await client.query(
          "INSERT INTO message_edits (message_id,editor_user_id,previous_body) VALUES ($1,$2,$3)",
          [existing.id, userId, existing.body],
        );
        const result = await client.query<{
          edited_at: Date;
        }>(
          "UPDATE messages SET body=$1,edited_at=now() WHERE id=$2 RETURNING edited_at",
          [body.body, existing.id],
        );
        return result.rows[0]?.edited_at;
      });
      if (!editedAt) throw new Error("Message edit failed");

      const event: RealtimeEvent = {
        id: randomUUID(),
        type: "message.updated",
        room: roomFor(existing),
        occurredAt: editedAt.toISOString(),
        payload: {
          id: existing.id,
          body: body.body,
          editedAt: editedAt.toISOString(),
        },
      };
      await publishRealtime(event);
      return event.payload;
    },
  );

  app.delete(
    "/messages/:messageId",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const query = z
        .object({
          scope: z.enum(["self", "everyone"]).default("everyone"),
        })
        .parse(request.query);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const existing = await messageAndRoom(params.messageId);
      if (!existing) {
        throw new AppError(404, "MESSAGE_NOT_FOUND", "Message not found");
      }
      await assertMessageAccess(userId, existing);

      if (query.scope === "self") {
        await pool.query(
          "INSERT INTO message_hidden_users (message_id,user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING",
          [existing.id, userId],
        );
        return { ok: true, scope: "self" };
      }

      let moderatorDelete = false;
      if (existing.sender_user_id !== userId) {
        moderatorDelete =
          existing.workspace_id !== null &&
          (await hasWorkspacePermission(
            userId,
            existing.workspace_id,
            "message.delete",
          ));

        if (!moderatorDelete) {
          throw new AppError(
            403,
            "MESSAGE_DELETE_DENIED",
            "You cannot delete this message for everyone",
          );
        }
      }

      await withTransaction(async (client) => {
        await client.query(
          "UPDATE messages SET deleted_at=now(),delete_scope='everyone',body='' WHERE id=$1",
          [existing.id],
        );

        if (moderatorDelete && existing.workspace_id) {
          await client.query(
            `INSERT INTO moderation_actions (
              workspace_id,actor_user_id,target_user_id,action,metadata
            ) VALUES ($1,$2,$3,'message.delete',$4::jsonb)`,
            [
              existing.workspace_id,
              userId,
              existing.sender_user_id,
              JSON.stringify({ messageId: existing.id }),
            ],
          );
          await recordAudit({
            client,
            workspaceId: existing.workspace_id,
            actorUserId: userId,
            action: "message.delete.moderator",
            target: { type: "message", id: existing.id },
            metadata: { senderUserId: existing.sender_user_id },
          });
        }
      });

      const event: RealtimeEvent = {
        id: randomUUID(),
        type: "message.deleted",
        room: roomFor(existing),
        occurredAt: new Date().toISOString(),
        payload: { id: existing.id },
      };
      await publishRealtime(event);
      return { ok: true, scope: "everyone" };
    },
  );

  app.put(
    "/messages/:messageId/reactions/:emoji",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          messageId: z.string().uuid(),
          emoji: z.string().min(1).max(32),
        })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");
      const existing = await messageAndRoom(params.messageId);
      if (!existing) {
        throw new AppError(404, "MESSAGE_NOT_FOUND", "Message not found");
      }
      await assertMessageAccess(userId, existing);

      await pool.query(
        "INSERT INTO message_reactions (message_id,user_id,emoji) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING",
        [params.messageId, userId, params.emoji],
      );
      const event: RealtimeEvent = {
        id: randomUUID(),
        type: "reaction.created",
        room: roomFor(existing),
        occurredAt: new Date().toISOString(),
        payload: {
          messageId: params.messageId,
          userId,
          emoji: params.emoji,
        },
      };
      await publishRealtime(event);
      return { ok: true };
    },
  );

  app.delete(
    "/messages/:messageId/reactions/:emoji",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          messageId: z.string().uuid(),
          emoji: z.string().min(1).max(32),
        })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");
      const existing = await messageAndRoom(params.messageId);
      if (!existing) {
        throw new AppError(404, "MESSAGE_NOT_FOUND", "Message not found");
      }
      await assertMessageAccess(userId, existing);

      await pool.query(
        "DELETE FROM message_reactions WHERE message_id=$1 AND user_id=$2 AND emoji=$3",
        [params.messageId, userId, params.emoji],
      );
      const event: RealtimeEvent = {
        id: randomUUID(),
        type: "reaction.deleted",
        room: roomFor(existing),
        occurredAt: new Date().toISOString(),
        payload: {
          messageId: params.messageId,
          userId,
          emoji: params.emoji,
        },
      };
      await publishRealtime(event);
      return { ok: true };
    },
  );
}
