import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { RealtimeEvent } from "@pulsemesh/realtime";
import { decodeCursor, encodeCursor } from "@pulsemesh/shared";
import { pool, withTransaction } from "../db/index.js";
import { AppError } from "../errors.js";
import { canAccessConversation } from "../authorization/service.js";
import { publishRealtime } from "../realtime/bus.js";
import { attachReadyFiles } from "../messages/attachments.js";
import { createMentionNotifications } from "../messages/mentions.js";
import { publishInboxMessageEvents } from "../messages/inbox-events.js";
import { messagesCreated } from "../observability/metrics.js";

type ConversationMessageRow = {
  id: string;
  body: string;
  encryption_version: string | null;
  encrypted_payload: string | null;
  created_at: Date;
  edited_at: Date | null;
  client_message_id: string | null;
  reply_to_message_id: string | null;
  sender_id: string;
  username: string;
  display_name: string;
  avatar_url: string | null;
  attachments: unknown[];
  reactions: unknown[];
};

const sendSchema = z
  .object({
    clientMessageId: z.string().uuid().optional(),
    body: z.string().trim().max(20_000).default(""),
    encryptionVersion: z.literal("libsignal-v1").optional(),
    encryptedPayload: z.string().min(1).max(262_144).optional(),
    replyToMessageId: z.string().uuid().optional(),
    attachmentIds: z.array(z.string().uuid()).max(10).default([]),
  })
  .refine(
    (value) =>
      value.body.length > 0 ||
      value.attachmentIds.length > 0 ||
      value.encryptedPayload !== undefined,
    {
      message: "A message must contain plaintext, ciphertext, or an attachment",
    },
  );

export async function conversationRoutes(app: FastifyInstance): Promise<void> {
  app.get(
    "/conversations",
    { preHandler: app.authenticate },
    async (request) => {
      const result = await pool.query(
        `SELECT
           c.id,
           c.kind,
           c.name,
           c.avatar_url,
           c.encryption_mode,
           c.created_at,
           COALESCE(unread.unread_count,0)::int AS unread_count,
           COALESCE(
             json_agg(
               json_build_object(
                 'id',u.id,
                 'username',u.username,
                 'displayName',u.display_name,
                 'avatarUrl',u.avatar_url
               )
               ORDER BY u.display_name
             ) FILTER (WHERE u.id IS NOT NULL),
             '[]'::json
           ) AS members
         FROM conversations c
         JOIN conversation_members mine
           ON mine.conversation_id=c.id AND mine.user_id=$1
         LEFT JOIN conversation_members cm
           ON cm.conversation_id=c.id
         LEFT JOIN users u
           ON u.id=cm.user_id
         LEFT JOIN read_states rs
           ON rs.user_id=$1 AND rs.conversation_id=c.id
         LEFT JOIN messages read_message
           ON read_message.id=rs.last_read_message_id
         LEFT JOIN LATERAL (
           SELECT count(*)::int AS unread_count
           FROM messages m
           WHERE m.conversation_id=c.id
             AND m.deleted_at IS NULL
             AND m.sender_user_id<>$1
             AND NOT EXISTS (
               SELECT 1
               FROM message_hidden_users hidden
               WHERE hidden.message_id=m.id AND hidden.user_id=$1
             )
             AND (
               read_message.id IS NULL
               OR (m.created_at,m.id) > (read_message.created_at,read_message.id)
             )
         ) unread ON TRUE
         GROUP BY c.id,unread.unread_count
         ORDER BY c.updated_at DESC,c.created_at DESC`,
        [request.auth?.userId],
      );
      return { items: result.rows };
    },
  );

  app.post(
    "/conversations",
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 20, timeWindow: "1 minute" } },
    },
    async (request, reply) => {
      const body = z
        .object({
          kind: z.enum(["direct", "group"]),
          memberIds: z.array(z.string().uuid()).min(1).max(49),
          name: z.string().min(1).max(100).optional(),
        })
        .parse(request.body);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const uniqueMemberIds = [
        ...new Set(body.memberIds.filter((id) => id !== userId)),
      ];

      const allowedMembers = await pool.query<{ id: string }>(
        `SELECT DISTINCT target.user_id AS id
         FROM workspace_members mine
         JOIN workspace_members target
           ON target.workspace_id=mine.workspace_id
         WHERE mine.user_id=$1
           AND target.user_id=ANY($2::uuid[])
           AND target.user_id<>$1`,
        [userId, uniqueMemberIds],
      );

      const allowedMemberIds = new Set(
        allowedMembers.rows.map((row) => row.id),
      );
      const unauthorizedMemberIds = uniqueMemberIds.filter(
        (id) => !allowedMemberIds.has(id),
      );

      if (unauthorizedMemberIds.length > 0) {
        throw new AppError(
          403,
          "CONVERSATION_MEMBER_NOT_SHARED",
          "Conversation members must share at least one workspace with you",
        );
      }

      if (body.kind === "direct" && uniqueMemberIds.length !== 1) {
        throw new AppError(
          400,
          "DIRECT_MEMBER_COUNT",
          "Direct conversations require exactly one other member",
        );
      }

      if (body.kind === "direct") {
        const existing = await pool.query<{ id: string }>(
          "SELECT c.id FROM conversations c JOIN conversation_members a ON a.conversation_id=c.id AND a.user_id=$1 JOIN conversation_members b ON b.conversation_id=c.id AND b.user_id=$2 WHERE c.kind='direct' AND (SELECT count(*) FROM conversation_members x WHERE x.conversation_id=c.id)=2 LIMIT 1",
          [userId, uniqueMemberIds[0]],
        );
        const row = existing.rows[0];
        if (row) return reply.send(row);
      }

      const created = await withTransaction(async (client) => {
        const result = await client.query<{
          id: string;
          kind: string;
          name: string | null;
        }>(
          "INSERT INTO conversations (kind,name,owner_user_id) VALUES ($1,$2,$3) RETURNING id,kind,name",
          [
            body.kind,
            body.kind === "group" ? (body.name ?? "New group") : null,
            userId,
          ],
        );
        const conversation = result.rows[0];
        if (!conversation) {
          throw new Error("Conversation creation failed");
        }

        await client.query(
          "INSERT INTO conversation_members (conversation_id,user_id,role) VALUES ($1,$2,'owner')",
          [conversation.id, userId],
        );

        for (const memberId of uniqueMemberIds) {
          await client.query(
            "INSERT INTO conversation_members (conversation_id,user_id,role) VALUES ($1,$2,'member') ON CONFLICT DO NOTHING",
            [conversation.id, memberId],
          );
        }

        return conversation;
      });

      return reply.code(201).send(created);
    },
  );

  app.get(
    "/conversations/:conversationId/messages",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      const query = z
        .object({
          cursor: z.string().optional(),
          limit: z.coerce.number().int().min(1).max(100).default(50),
        })
        .parse(request.query);
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

      const values: unknown[] = [params.conversationId, userId];
      let cursorClause = "";

      if (query.cursor) {
        const cursor = decodeCursor<{
          createdAt: string;
          id: string;
        }>(query.cursor);
        values.push(cursor.createdAt, cursor.id);
        cursorClause = "AND (m.created_at,m.id) < ($3::timestamptz,$4::uuid)";
      }
      values.push(query.limit + 1);

      const result = await pool.query<ConversationMessageRow>(
        "SELECT m.id,m.body,m.encryption_version,m.encrypted_payload,m.created_at,m.edited_at,m.client_message_id,m.reply_to_message_id,u.id AS sender_id,u.username,u.display_name,u.avatar_url,COALESCE((SELECT json_agg(json_build_object('id',f.id,'name',f.original_name,'mimeType',COALESCE(f.detected_mime_type,f.mime_type),'sizeBytes',f.size_bytes,'width',f.width,'height',f.height,'durationMs',f.duration_ms,'hasThumbnail',(f.thumbnail_key IS NOT NULL)) ORDER BY ma.position) FROM message_attachments ma JOIN files f ON f.id=ma.file_id WHERE ma.message_id=m.id AND f.status='ready'),'[]'::json) AS attachments,COALESCE((SELECT json_agg(json_build_object('emoji',r.emoji,'count',r.count,'reactedByMe',EXISTS (SELECT 1 FROM message_reactions mine WHERE mine.message_id=m.id AND mine.user_id=$2 AND mine.emoji=r.emoji)) ORDER BY r.count DESC,r.emoji) FROM (SELECT mr.emoji,count(*)::int AS count FROM message_reactions mr WHERE mr.message_id=m.id GROUP BY mr.emoji) r),'[]'::json) AS reactions FROM messages m JOIN users u ON u.id=m.sender_user_id WHERE m.conversation_id=$1 AND m.deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM message_hidden_users h WHERE h.message_id=m.id AND h.user_id=$2) " +
          cursorClause +
          " ORDER BY m.created_at DESC,m.id DESC LIMIT $" +
          values.length,
        values,
      );

      const hasMore = result.rows.length > query.limit;
      const rows = result.rows.slice(0, query.limit);
      const last = rows[rows.length - 1];

      return {
        items: rows.map((row) => ({
          id: row.id,
          clientMessageId: row.client_message_id,
          channelId: null,
          conversationId: params.conversationId,
          body: row.body,
          encryptionVersion: row.encryption_version,
          encryptedPayload: row.encrypted_payload,
          replyToMessageId: row.reply_to_message_id,
          attachments: row.attachments,
          reactions: row.reactions,
          createdAt: row.created_at.toISOString(),
          editedAt: row.edited_at?.toISOString() ?? null,
          sender: {
            id: row.sender_id,
            username: row.username,
            displayName: row.display_name,
            avatarUrl: row.avatar_url,
          },
        })),
        nextCursor:
          hasMore && last
            ? encodeCursor({
                createdAt: last.created_at.toISOString(),
                id: last.id,
              })
            : null,
      };
    },
  );

  app.post(
    "/conversations/:conversationId/messages",
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 60, timeWindow: "1 minute" } },
    },
    async (request, reply) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      const body = sendSchema.parse(request.body);
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

      const conversation = await pool.query<{
        encryption_mode: "none" | "e2ee_v1";
      }>("SELECT encryption_mode FROM conversations WHERE id=$1", [
        params.conversationId,
      ]);
      const encryptionMode = conversation.rows[0]?.encryption_mode ?? "none";

      if (encryptionMode === "e2ee_v1") {
        if (
          body.encryptionVersion !== "libsignal-v1" ||
          !body.encryptedPayload ||
          body.body.length > 0 ||
          body.attachmentIds.length > 0
        ) {
          throw new AppError(
            400,
            "E2EE_CIPHERTEXT_REQUIRED",
            "Encrypted conversations accept only libsignal ciphertext in the initial E2EE release",
          );
        }
      } else if (
        body.encryptionVersion !== undefined ||
        body.encryptedPayload !== undefined
      ) {
        throw new AppError(
          409,
          "E2EE_NOT_ENABLED",
          "End-to-end encryption is not enabled for this conversation",
        );
      }

      const created = await withTransaction(async (client) => {
        const result = await client.query<{
          id: string;
          created_at: Date;
          client_message_id: string | null;
        }>(
          "INSERT INTO messages (conversation_id,sender_user_id,client_message_id,body,encryption_version,encrypted_payload,reply_to_message_id) VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (sender_user_id,client_message_id) WHERE client_message_id IS NOT NULL DO UPDATE SET client_message_id=EXCLUDED.client_message_id RETURNING id,created_at,client_message_id",
          [
            params.conversationId,
            userId,
            body.clientMessageId ?? null,
            body.body,
            body.encryptionVersion ?? null,
            body.encryptedPayload ?? null,
            body.replyToMessageId ?? null,
          ],
        );
        const message = result.rows[0];
        if (!message) throw new Error("Message creation failed");

        const attachmentIds = await attachReadyFiles(
          client,
          message.id,
          userId,
          body.attachmentIds,
        );

        await client.query(
          "UPDATE conversations SET updated_at=now() WHERE id=$1",
          [params.conversationId],
        );

        return { message, attachmentIds };
      });

      if (encryptionMode === "none") {
        await createMentionNotifications({
          messageId: created.message.id,
          senderUserId: userId,
          body: body.body,
          conversationId: params.conversationId,
        });
      }

      const event: RealtimeEvent = {
        id: randomUUID(),
        type: "message.created",
        room: "conversation:" + params.conversationId,
        occurredAt: new Date().toISOString(),
        payload: {
          id: created.message.id,
          channelId: null,
          conversationId: params.conversationId,
          senderId: userId,
          body: body.body,
          encryptionVersion: body.encryptionVersion ?? null,
          encryptedPayload: body.encryptedPayload ?? null,
          clientMessageId: created.message.client_message_id,
          attachmentIds: created.attachmentIds,
          createdAt: created.message.created_at.toISOString(),
        },
      };

      await publishRealtime(event);
      await publishInboxMessageEvents({
        messageId: created.message.id,
        senderUserId: userId,
        channelId: null,
        conversationId: params.conversationId,
        createdAt: created.message.created_at,
      });
      messagesCreated.inc({ destination: "conversation" });
      return reply.code(201).send(event.payload);
    },
  );
}
