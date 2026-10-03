import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool } from "../db/index.js";

export async function callHistoryRoutes(app: FastifyInstance): Promise<void> {
  app.get(
    "/calls/history",
    { preHandler: app.authenticate },
    async (request) => {
      const query = z
        .object({
          limit: z.coerce.number().int().min(1).max(100).default(50),
          conversationId: z.string().uuid().optional(),
        })
        .parse(request.query);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const result = await pool.query<{
        id: string;
        conversation_id: string | null;
        created_by: string;
        creator_username: string;
        creator_display_name: string;
        kind: "voice" | "video";
        status: string;
        started_at: Date;
        ended_at: Date | null;
        invite_status: string | null;
        joined: boolean;
      }>(
        `SELECT DISTINCT
           c.id,
           c.conversation_id,
           c.created_by,
           u.username AS creator_username,
           u.display_name AS creator_display_name,
           c.kind,
           c.status,
           c.started_at,
           c.ended_at,
           ci.status AS invite_status,
           EXISTS (
             SELECT 1 FROM call_participants cp
             WHERE cp.call_id=c.id AND cp.user_id=$1
           ) AS joined
         FROM calls c
         JOIN users u ON u.id=c.created_by
         LEFT JOIN call_invites ci ON ci.call_id=c.id AND ci.user_id=$1
         WHERE c.conversation_id IS NOT NULL
           AND (
             c.created_by=$1
             OR ci.user_id=$1
             OR EXISTS (
               SELECT 1 FROM call_participants cp2
               WHERE cp2.call_id=c.id AND cp2.user_id=$1
             )
           )
           AND ($2::uuid IS NULL OR c.conversation_id=$2::uuid)
         ORDER BY c.started_at DESC, c.id DESC
         LIMIT $3`,
        [userId, query.conversationId ?? null, query.limit],
      );

      return {
        items: result.rows.map((row) => ({
          id: row.id,
          conversationId: row.conversation_id,
          createdBy: row.created_by,
          creatorUsername: row.creator_username,
          creatorDisplayName: row.creator_display_name,
          kind: row.kind,
          status: row.status,
          startedAt: row.started_at.toISOString(),
          endedAt: row.ended_at?.toISOString() ?? null,
          inviteStatus: row.invite_status,
          joined: row.joined,
          direction: row.created_by === userId ? "outgoing" : "incoming",
          missed:
            row.created_by !== userId &&
            (row.invite_status === "missed" ||
              (row.invite_status === "declined" && !row.joined)),
        })),
      };
    },
  );
}
