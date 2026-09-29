import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { RealtimeEvent } from "@pulsemesh/realtime";
import { pool } from "../db/index.js";
import { AppError } from "../errors.js";
import {
  assertWorkspacePermission,
  canAccessChannel,
  canAccessConversation,
  canSendToChannel,
} from "../authorization/service.js";
import { publishRealtime } from "../realtime/bus.js";
import { createMentionNotifications } from "./mentions.js";

type MessageLocation = {
  id: string;
  sender_user_id: string;
  body: string;
  channel_id: string | null;
  conversation_id: string | null;
};

async function getMessage(messageId: string): Promise<MessageLocation> {
  const result = await pool.query<MessageLocation>(
    "SELECT id,sender_user_id,body,channel_id,conversation_id FROM messages WHERE id=$1 AND deleted_at IS NULL",
    [messageId],
  );
  const message = result.rows[0];
  if (!message) {
    throw new AppError(404, "MESSAGE_NOT_FOUND", "Message not found");
  }
  return message;
}

async function assertMessageAccess(
  userId: string,
  message: MessageLocation,
): Promise<void> {
  if (message.channel_id) {
    if (!(await canAccessChannel(userId, message.channel_id))) {
      throw new AppError(403, "MESSAGE_ACCESS_DENIED", "Message access denied");
    }
    return;
  }

  if (
    !message.conversation_id ||
    !(await canAccessConversation(userId, message.conversation_id))
  ) {
    throw new AppError(403, "MESSAGE_ACCESS_DENIED", "Message access denied");
  }
}

async function assertConversationAdmin(
  userId: string,
  conversationId: string,
): Promise<void> {
  const result = await pool.query<{ role: string }>(
    "SELECT role FROM conversation_members WHERE conversation_id=$1 AND user_id=$2",
    [conversationId, userId],
  );

  if (!["owner", "admin"].includes(result.rows[0]?.role ?? "")) {
    throw new AppError(
      403,
      "CONVERSATION_ADMIN_REQUIRED",
      "Conversation admin permission required",
    );
  }
}

async function publishCreatedMessage(input: {
  messageId: string;
  senderUserId: string;
  body: string;
  clientMessageId: string | null;
  createdAt: Date;
  channelId: string | null;
  conversationId: string | null;
}): Promise<void> {
  const room = input.channelId
    ? "channel:" + input.channelId
    : "conversation:" + input.conversationId;

  const event: RealtimeEvent = {
    id: randomUUID(),
    type: "message.created",
    room,
    occurredAt: input.createdAt.toISOString(),
    payload: {
      id: input.messageId,
      channelId: input.channelId,
      conversationId: input.conversationId,
      senderId: input.senderUserId,
      body: input.body,
      clientMessageId: input.clientMessageId,
      createdAt: input.createdAt.toISOString(),
    },
  };

  await publishRealtime(event);
}

export async function coreMessagingRoutes(app: FastifyInstance): Promise<void> {
  app.get(
    "/messages/:messageId/thread",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const root = await getMessage(params.messageId);
      await assertMessageAccess(userId, root);

      const result = await pool.query(
        "SELECT m.id,m.body,m.created_at,m.edited_at,m.client_message_id,m.reply_to_message_id,m.thread_root_message_id,u.id AS sender_id,u.username,u.display_name,u.avatar_url FROM messages m JOIN users u ON u.id=m.sender_user_id WHERE m.thread_root_message_id=$1 AND m.deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM message_hidden_users h WHERE h.message_id=m.id AND h.user_id=$2) ORDER BY m.created_at,m.id",
        [root.id, userId],
      );

      return { root, items: result.rows };
    },
  );

  app.post(
    "/messages/:messageId/thread",
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 60, timeWindow: "1 minute" } },
    },
    async (request, reply) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          clientMessageId: z.string().uuid().optional(),
          body: z.string().trim().min(1).max(20_000),
        })
        .parse(request.body);

      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const root = await getMessage(params.messageId);
      await assertMessageAccess(userId, root);

      if (
        root.channel_id &&
        !(await canSendToChannel(userId, root.channel_id))
      ) {
        throw new AppError(
          403,
          "MESSAGE_SEND_DENIED",
          "You cannot send to this channel",
        );
      }

      const result = await pool.query<{
        id: string;
        created_at: Date;
        client_message_id: string | null;
      }>(
        "INSERT INTO messages (channel_id,conversation_id,sender_user_id,client_message_id,body,reply_to_message_id,thread_root_message_id) VALUES ($1,$2,$3,$4,$5,$6,$6) ON CONFLICT (sender_user_id,client_message_id) WHERE client_message_id IS NOT NULL DO UPDATE SET client_message_id=EXCLUDED.client_message_id RETURNING id,created_at,client_message_id",
        [
          root.channel_id,
          root.conversation_id,
          userId,
          body.clientMessageId ?? null,
          body.body,
          root.id,
        ],
      );

      const message = result.rows[0];
      if (!message) throw new Error("Thread reply creation failed");

      await createMentionNotifications({
        messageId: message.id,
        senderUserId: userId,
        body: body.body,
        ...(root.channel_id ? { channelId: root.channel_id } : {}),
        ...(root.conversation_id
          ? { conversationId: root.conversation_id }
          : {}),
      });

      await publishCreatedMessage({
        messageId: message.id,
        senderUserId: userId,
        body: body.body,
        clientMessageId: message.client_message_id,
        createdAt: message.created_at,
        channelId: root.channel_id,
        conversationId: root.conversation_id,
      });

      return reply.code(201).send({
        id: message.id,
        threadRootMessageId: root.id,
        createdAt: message.created_at.toISOString(),
      });
    },
  );

  app.post(
    "/messages/:messageId/forward",
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
    },
    async (request, reply) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          clientMessageId: z.string().uuid().optional(),
          channelId: z.string().uuid().optional(),
          conversationId: z.string().uuid().optional(),
        })
        .refine(
          (value) => Boolean(value.channelId) !== Boolean(value.conversationId),
          { message: "Exactly one destination is required" },
        )
        .parse(request.body);

      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const source = await getMessage(params.messageId);
      await assertMessageAccess(userId, source);

      if (body.channelId && !(await canSendToChannel(userId, body.channelId))) {
        throw new AppError(
          403,
          "MESSAGE_SEND_DENIED",
          "You cannot send to this channel",
        );
      }

      if (
        body.conversationId &&
        !(await canAccessConversation(userId, body.conversationId))
      ) {
        throw new AppError(
          403,
          "CONVERSATION_ACCESS_DENIED",
          "Conversation access denied",
        );
      }

      const result = await pool.query<{
        id: string;
        created_at: Date;
        client_message_id: string | null;
      }>(
        "INSERT INTO messages (channel_id,conversation_id,sender_user_id,client_message_id,body,forwarded_from_message_id) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (sender_user_id,client_message_id) WHERE client_message_id IS NOT NULL DO UPDATE SET client_message_id=EXCLUDED.client_message_id RETURNING id,created_at,client_message_id",
        [
          body.channelId ?? null,
          body.conversationId ?? null,
          userId,
          body.clientMessageId ?? null,
          source.body,
          source.id,
        ],
      );

      const forwarded = result.rows[0];
      if (!forwarded) throw new Error("Forward failed");

      await publishCreatedMessage({
        messageId: forwarded.id,
        senderUserId: userId,
        body: source.body,
        clientMessageId: forwarded.client_message_id,
        createdAt: forwarded.created_at,
        channelId: body.channelId ?? null,
        conversationId: body.conversationId ?? null,
      });

      return reply.code(201).send({
        id: forwarded.id,
        forwardedFromMessageId: source.id,
        createdAt: forwarded.created_at.toISOString(),
      });
    },
  );

  app.get("/bookmarks", { preHandler: app.authenticate }, async (request) => {
    const result = await pool.query(
      "SELECT b.message_id,b.note,b.created_at,b.updated_at,m.body,m.channel_id,m.conversation_id,m.created_at AS message_created_at,u.id AS sender_id,u.username,u.display_name,u.avatar_url FROM bookmarks b JOIN messages m ON m.id=b.message_id JOIN users u ON u.id=m.sender_user_id WHERE b.user_id=$1 ORDER BY b.updated_at DESC",
      [request.auth?.userId],
    );
    return { items: result.rows };
  });

  app.put(
    "/messages/:messageId/bookmark",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({ note: z.string().max(1000).nullable().optional() })
        .parse(request.body);

      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const message = await getMessage(params.messageId);
      await assertMessageAccess(userId, message);

      await pool.query(
        "INSERT INTO bookmarks (user_id,message_id,note) VALUES ($1,$2,$3) ON CONFLICT (user_id,message_id) DO UPDATE SET note=EXCLUDED.note,updated_at=now()",
        [userId, message.id, body.note ?? null],
      );

      return { ok: true };
    },
  );

  app.delete(
    "/messages/:messageId/bookmark",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);

      await pool.query(
        "DELETE FROM bookmarks WHERE user_id=$1 AND message_id=$2",
        [request.auth?.userId, params.messageId],
      );

      return { ok: true };
    },
  );

  app.post(
    "/messages/:messageId/pin",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const message = await getMessage(params.messageId);
      await assertMessageAccess(userId, message);

      if (message.channel_id) {
        const workspace = await pool.query<{ workspace_id: string }>(
          "SELECT workspace_id FROM channels WHERE id=$1",
          [message.channel_id],
        );
        const workspaceId = workspace.rows[0]?.workspace_id;
        if (!workspaceId) {
          throw new AppError(404, "CHANNEL_NOT_FOUND", "Channel not found");
        }
        await assertWorkspacePermission(userId, workspaceId, "message.pin");
      } else if (message.conversation_id) {
        await assertConversationAdmin(userId, message.conversation_id);
      }

      await pool.query(
        "INSERT INTO message_pins (message_id,channel_id,conversation_id,pinned_by) VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING",
        [message.id, message.channel_id, message.conversation_id, userId],
      );

      return { ok: true };
    },
  );

  app.delete(
    "/messages/:messageId/pin",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const message = await getMessage(params.messageId);
      await assertMessageAccess(userId, message);

      if (message.channel_id) {
        const workspace = await pool.query<{ workspace_id: string }>(
          "SELECT workspace_id FROM channels WHERE id=$1",
          [message.channel_id],
        );
        const workspaceId = workspace.rows[0]?.workspace_id;
        if (!workspaceId) {
          throw new AppError(404, "CHANNEL_NOT_FOUND", "Channel not found");
        }
        await assertWorkspacePermission(userId, workspaceId, "message.pin");
      } else if (message.conversation_id) {
        await assertConversationAdmin(userId, message.conversation_id);
      }

      await pool.query("DELETE FROM message_pins WHERE message_id=$1", [
        message.id,
      ]);

      return { ok: true };
    },
  );

  app.get(
    "/channels/:channelId/pins",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;

      if (!userId || !(await canAccessChannel(userId, params.channelId))) {
        throw new AppError(
          403,
          "CHANNEL_ACCESS_DENIED",
          "Channel access denied",
        );
      }

      const result = await pool.query(
        "SELECT p.created_at AS pinned_at,m.id,m.body,m.created_at,u.id AS sender_id,u.username,u.display_name FROM message_pins p JOIN messages m ON m.id=p.message_id JOIN users u ON u.id=m.sender_user_id WHERE p.channel_id=$1 AND m.deleted_at IS NULL ORDER BY p.created_at DESC",
        [params.channelId],
      );

      return { items: result.rows };
    },
  );

  app.get(
    "/conversations/:conversationId/pins",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;

      if (
        !userId ||
        !(await canAccessConversation(userId, params.conversationId))
      ) {
        throw new AppError(
          403,
          "CONVERSATION_ACCESS_DENIED",
          "Conversation access denied",
        );
      }

      const result = await pool.query(
        "SELECT p.created_at AS pinned_at,m.id,m.body,m.created_at,u.id AS sender_id,u.username,u.display_name FROM message_pins p JOIN messages m ON m.id=p.message_id JOIN users u ON u.id=m.sender_user_id WHERE p.conversation_id=$1 AND m.deleted_at IS NULL ORDER BY p.created_at DESC",
        [params.conversationId],
      );

      return { items: result.rows };
    },
  );
}
