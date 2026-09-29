import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool } from "../db/index.js";
import { assertWorkspacePermission } from "../authorization/service.js";

export async function auditRoutes(app: FastifyInstance): Promise<void> {
  app.get(
    "/workspaces/:workspaceId/audit-logs",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ workspaceId: z.string().uuid() })
        .parse(request.params);
      const query = z
        .object({
          before: z.string().regex(/^\d+$/).optional(),
          limit: z.coerce.number().int().min(1).max(100).default(50),
        })
        .parse(request.query);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing authenticated user");

      await assertWorkspacePermission(userId, params.workspaceId, "audit.view");

      const values: unknown[] = [params.workspaceId];
      let beforeClause = "";
      if (query.before) {
        values.push(query.before);
        beforeClause = "AND a.id < $2::bigint";
      }
      values.push(query.limit + 1);

      const result = await pool.query(
        `SELECT
          a.id::text,a.action,a.target_type,a.target_id,a.metadata,a.created_at,
          a.actor_user_id,u.display_name AS actor_name,u.username AS actor_username
         FROM audit_logs a
         LEFT JOIN users u ON u.id=a.actor_user_id
         WHERE a.workspace_id=$1
         ${beforeClause}
         ORDER BY a.id DESC
         LIMIT $${values.length}`,
        values,
      );

      const hasMore = result.rows.length > query.limit;
      const items = result.rows.slice(0, query.limit);
      return {
        items,
        nextBefore:
          hasMore && items.length > 0
            ? (items[items.length - 1]?.id ?? null)
            : null,
      };
    },
  );
}
