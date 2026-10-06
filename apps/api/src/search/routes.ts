import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool } from "../db/index.js";

export async function searchRoutes(app: FastifyInstance): Promise<void> {
  app.get("/search", { preHandler: app.authenticate }, async (request) => {
    const query = z
      .object({
        q: z.string().trim().min(2).max(200),
        limit: z.coerce.number().int().min(1).max(50).default(20),
      })
      .parse(request.query);
    const userId = request.auth?.userId;

    const messages = await pool.query(
      `SELECT m.id,m.body,m.channel_id,m.conversation_id,m.created_at,u.username,u.display_name,
        ts_rank(to_tsvector('simple',m.body),plainto_tsquery('simple',$2)) AS rank
       FROM messages m
       JOIN users u ON u.id=m.sender_user_id
       LEFT JOIN channels c ON c.id=m.channel_id
       LEFT JOIN workspace_members wm
         ON wm.workspace_id=c.workspace_id AND wm.user_id=$1
       LEFT JOIN channel_members chm
         ON chm.channel_id=c.id AND chm.user_id=$1
       LEFT JOIN conversation_members cm
         ON cm.conversation_id=m.conversation_id AND cm.user_id=$1
       WHERE m.deleted_at IS NULL
         AND (
           (m.channel_id IS NOT NULL
             AND wm.user_id IS NOT NULL
             AND (c.visibility<>'private' OR chm.user_id IS NOT NULL))
           OR
           (m.conversation_id IS NOT NULL AND cm.user_id IS NOT NULL)
         )
         AND to_tsvector('simple',m.body) @@ plainto_tsquery('simple',$2)
       ORDER BY rank DESC,m.created_at DESC
       LIMIT $3`,
      [userId, query.q, query.limit],
    );

    const users = await pool.query(
      "SELECT DISTINCT u.id,u.username,u.display_name,u.avatar_url FROM users u JOIN workspace_members target ON target.user_id=u.id JOIN workspace_members mine ON mine.workspace_id=target.workspace_id AND mine.user_id=$1 WHERE u.id<>$1 AND (u.username ILIKE $2 OR u.display_name ILIKE $2) ORDER BY u.display_name LIMIT 10",
      [userId, "%" + query.q + "%"],
    );

    const channels = await pool.query(
      `SELECT c.id,c.name,c.workspace_id
       FROM channels c
       JOIN workspace_members wm ON wm.workspace_id=c.workspace_id
       LEFT JOIN channel_members cm
         ON cm.channel_id=c.id AND cm.user_id=$1
       WHERE wm.user_id=$1
         AND c.name ILIKE $2
         AND c.archived_at IS NULL
         AND (c.visibility<>'private' OR cm.user_id IS NOT NULL)
       ORDER BY c.name
       LIMIT 10`,
      [userId, "%" + query.q + "%"],
    );

    return {
      messages: messages.rows,
      users: users.rows,
      channels: channels.rows,
    };
  });
}
