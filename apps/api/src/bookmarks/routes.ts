import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { decodeCursor, encodeCursor } from "@pulsemesh/shared";
import {
  canAccessChannel,
  canAccessConversation,
} from "../authorization/service.js";
import { pool } from "../db/index.js";
import { AppError } from "../errors.js";

const bookmarkBodySchema = z.object({
  note: z.string().trim().max(2_000).nullable().optional(),
});

async function assertMessageAccess(
  userId: string,
  messageId: string,
): Promise<void> {
  const result = await pool.query<{
    channel_id: string | null;
    conversation_id: string | null;
  }>(
    "SELECT channel_id,conversation_id FROM messages WHERE id=$1 AND deleted_at IS NULL",
    [messageId],
  );
  const message = result.rows[0];
  if (!message) {
    throw new AppError(404, "MESSAGE_NOT_FOUND", "Message not found");
  }

  const allowed = message.channel_id
    ? await canAccessChannel(userId, message.channel_id)
    : message.conversation_id
      ? await canAccessConversation(userId, message.conversation_id)
      : false;

  if (!allowed) {
    throw new AppError(403, "MESSAGE_ACCESS_DENIED", "Message access denied");
  }
}

export async function bookmarkRoutes(app: FastifyInstance): Promise<void> {
  app.get("/bookmarks", { preHandler: app.authenticate }, async (request) => {
    const query = z
      .object({
        cursor: z.string().optional(),
        limit: z.coerce.number().int().min(1).max(100).default(50),
      })
      .parse(request.query);
    const userId = request.auth?.userId;
    if (!userId) throw new Error("Missing authenticated user");

    const values: unknown[] = [userId];
    let cursorClause = "";
    if (query.cursor) {
      const cursor = decodeCursor<{
        createdAt: string;
        messageId: string;
      }>(query.cursor);
      values.push(cursor.createdAt, cursor.messageId);
      cursorClause =
        "AND (b.created_at,b.message_id) < ($2::timestamptz,$3::uuid)";
    }
    values.push(query.limit + 1);

    const result = await pool.query<{
      message_id: string;
      note: string | null;
      bookmark_created_at: Date;
      bookmark_updated_at: Date;
      body: string;
      message_created_at: Date;
      edited_at: Date | null;
      channel_id: string | null;
      conversation_id: string | null;
      sender_id: string;
      username: string;
      display_name: string;
      avatar_url: string | null;
    }>(
      `SELECT
          b.message_id,b.note,b.created_at AS bookmark_created_at,
          b.updated_at AS bookmark_updated_at,m.body,
          m.created_at AS message_created_at,m.edited_at,m.channel_id,
          m.conversation_id,u.id AS sender_id,u.username,u.display_name,u.avatar_url
         FROM message_bookmarks b
         JOIN messages m ON m.id=b.message_id
         JOIN users u ON u.id=m.sender_user_id
         WHERE b.user_id=$1
           AND m.deleted_at IS NULL
           AND (
             (
               m.channel_id IS NOT NULL
               AND EXISTS (
                 SELECT 1
                 FROM channels c
                 JOIN workspace_members wm ON wm.workspace_id=c.workspace_id
                 LEFT JOIN channel_members cm
                   ON cm.channel_id=c.id AND cm.user_id=wm.user_id
                 WHERE c.id=m.channel_id
                   AND wm.user_id=$1
                   AND (c.visibility <> 'private' OR cm.user_id IS NOT NULL)
               )
             )
             OR (
               m.conversation_id IS NOT NULL
               AND EXISTS (
                 SELECT 1 FROM conversation_members member
                 WHERE member.conversation_id=m.conversation_id
                   AND member.user_id=$1
               )
             )
           )
           ${cursorClause}
         ORDER BY b.created_at DESC,b.message_id DESC
         LIMIT $${values.length}`,
      values,
    );

    const hasMore = result.rows.length > query.limit;
    const rows = result.rows.slice(0, query.limit);
    const last = rows[rows.length - 1];

    return {
      items: rows.map((row) => ({
        messageId: row.message_id,
        note: row.note,
        createdAt: row.bookmark_created_at.toISOString(),
        updatedAt: row.bookmark_updated_at.toISOString(),
        message: {
          id: row.message_id,
          channelId: row.channel_id,
          conversationId: row.conversation_id,
          body: row.body,
          createdAt: row.message_created_at.toISOString(),
          editedAt: row.edited_at?.toISOString() ?? null,
          sender: {
            id: row.sender_id,
            username: row.username,
            displayName: row.display_name,
            avatarUrl: row.avatar_url,
          },
        },
      })),
      nextCursor:
        hasMore && last
          ? encodeCursor({
              createdAt: last.bookmark_created_at.toISOString(),
              messageId: last.message_id,
            })
          : null,
    };
  });

  app.put(
    "/messages/:messageId/bookmark",
    { preHandler: app.authenticate },
    async (request, reply) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const body = bookmarkBodySchema.parse(request.body ?? {});
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing authenticated user");

      await assertMessageAccess(userId, params.messageId);

      const result = await pool.query<{
        message_id: string;
        note: string | null;
        created_at: Date;
        updated_at: Date;
      }>(
        `INSERT INTO message_bookmarks (user_id,message_id,note)
         VALUES ($1,$2,$3)
         ON CONFLICT (user_id,message_id)
         DO UPDATE SET note=EXCLUDED.note,updated_at=now()
         RETURNING message_id,note,created_at,updated_at`,
        [userId, params.messageId, body.note ?? null],
      );
      const bookmark = result.rows[0];
      if (!bookmark) throw new Error("Bookmark upsert failed");

      return reply.send({
        messageId: bookmark.message_id,
        note: bookmark.note,
        createdAt: bookmark.created_at.toISOString(),
        updatedAt: bookmark.updated_at.toISOString(),
      });
    },
  );

  app.delete(
    "/messages/:messageId/bookmark",
    { preHandler: app.authenticate },
    async (request, reply) => {
      const params = z
        .object({ messageId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing authenticated user");

      await pool.query(
        "DELETE FROM message_bookmarks WHERE user_id=$1 AND message_id=$2",
        [userId, params.messageId],
      );
      return reply.code(204).send();
    },
  );
}
