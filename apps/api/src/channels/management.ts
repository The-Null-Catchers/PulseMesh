import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool, withTransaction } from "../db/index.js";
import { AppError } from "../errors.js";
import {
  assertWorkspacePermission,
  canAccessChannel,
} from "../authorization/service.js";

async function workspaceForChannel(channelId: string): Promise<string> {
  const result = await pool.query<{ workspace_id: string }>(
    "SELECT workspace_id FROM channels WHERE id=$1",
    [channelId],
  );
  const workspaceId = result.rows[0]?.workspace_id;
  if (!workspaceId) {
    throw new AppError(404, "CHANNEL_NOT_FOUND", "Channel not found");
  }
  return workspaceId;
}

export async function channelManagementRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.patch(
    "/channels/:channelId",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          name: z
            .string()
            .min(1)
            .max(80)
            .regex(/^[a-z0-9-]+$/)
            .optional(),
          topic: z.string().max(500).nullable().optional(),
          visibility: z
            .enum(["public", "private", "read-only", "announcement"])
            .optional(),
        })
        .parse(request.body);

      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const workspaceId = await workspaceForChannel(params.channelId);
      await assertWorkspacePermission(userId, workspaceId, "channel.update");

      const result = await pool.query(
        "UPDATE channels SET name=COALESCE($1,name),topic=CASE WHEN $2::boolean THEN $3 ELSE topic END,visibility=COALESCE($4,visibility),updated_at=now() WHERE id=$5 RETURNING id,name,topic,kind,visibility,position,archived_at",
        [
          body.name ?? null,
          Object.prototype.hasOwnProperty.call(body, "topic"),
          body.topic ?? null,
          body.visibility ?? null,
          params.channelId,
        ],
      );

      return result.rows[0];
    },
  );

  app.post(
    "/channels/:channelId/archive",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const workspaceId = await workspaceForChannel(params.channelId);
      await assertWorkspacePermission(userId, workspaceId, "channel.delete");

      await pool.query(
        "UPDATE channels SET archived_at=COALESCE(archived_at,now()),updated_at=now() WHERE id=$1",
        [params.channelId],
      );

      return { ok: true };
    },
  );

  app.post(
    "/workspaces/:workspaceId/channels/reorder",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ workspaceId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          channelIds: z.array(z.string().uuid()).min(1).max(500),
        })
        .parse(request.body);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      await assertWorkspacePermission(
        userId,
        params.workspaceId,
        "channel.update",
      );

      await withTransaction(async (client) => {
        const existing = await client.query<{ id: string }>(
          "SELECT id FROM channels WHERE workspace_id=$1 AND id=ANY($2::uuid[])",
          [params.workspaceId, body.channelIds],
        );

        if (existing.rowCount !== body.channelIds.length) {
          throw new AppError(
            400,
            "INVALID_CHANNEL_ORDER",
            "All channels must belong to the workspace",
          );
        }

        for (let index = 0; index < body.channelIds.length; index += 1) {
          await client.query(
            "UPDATE channels SET position=$1,updated_at=now() WHERE id=$2 AND workspace_id=$3",
            [index, body.channelIds[index], params.workspaceId],
          );
        }
      });

      return { ok: true };
    },
  );

  app.get(
    "/channels/:channelId/preferences",
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
        "SELECT pinned,muted_until,notification_level,updated_at FROM channel_preferences WHERE user_id=$1 AND channel_id=$2",
        [userId, params.channelId],
      );

      return (
        result.rows[0] ?? {
          pinned: false,
          muted_until: null,
          notification_level: null,
        }
      );
    },
  );

  app.put(
    "/channels/:channelId/preferences",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          pinned: z.boolean().default(false),
          mutedUntil: z.string().datetime().nullable().default(null),
          notificationLevel: z
            .enum(["all", "mentions", "nothing"])
            .nullable()
            .default(null),
        })
        .parse(request.body);
      const userId = request.auth?.userId;

      if (!userId || !(await canAccessChannel(userId, params.channelId))) {
        throw new AppError(
          403,
          "CHANNEL_ACCESS_DENIED",
          "Channel access denied",
        );
      }

      await pool.query(
        "INSERT INTO channel_preferences (user_id,channel_id,pinned,muted_until,notification_level) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (user_id,channel_id) DO UPDATE SET pinned=EXCLUDED.pinned,muted_until=EXCLUDED.muted_until,notification_level=EXCLUDED.notification_level,updated_at=now()",
        [
          userId,
          params.channelId,
          body.pinned,
          body.mutedUntil,
          body.notificationLevel,
        ],
      );

      return { ok: true };
    },
  );
}
