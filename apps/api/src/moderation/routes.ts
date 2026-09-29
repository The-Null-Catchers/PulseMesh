import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool, withTransaction } from "../db/index.js";
import { AppError } from "../errors.js";
import { isWorkspaceMember } from "../authorization/service.js";
import { recordAudit } from "../audit/service.js";
import {
  assertModerationPermission,
  assertReportTarget,
  assertWorkspaceTargetMember,
  channelWorkspaceId,
} from "./service.js";
import { invalidateModerationRules } from "./anti-spam.js";

function actor(request: { auth?: { userId?: string } | null }) {
  const userId = request.auth?.userId;
  if (!userId) throw new Error("Missing authenticated user");
  return userId;
}

export async function moderationRoutes(app: FastifyInstance): Promise<void> {
  app.post(
    "/workspaces/:workspaceId/reports",
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 10, timeWindow: "1 minute" } },
    },
    async (request, reply) => {
      const params = z
        .object({ workspaceId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          reportedUserId: z.string().uuid().optional(),
          messageId: z.string().uuid().optional(),
          reason: z.string().trim().min(3).max(1000),
        })
        .parse(request.body);
      const userId = actor(request);

      if (!(await isWorkspaceMember(userId, params.workspaceId))) {
        throw new AppError(
          403,
          "WORKSPACE_ACCESS_DENIED",
          "Workspace access denied",
        );
      }

      await assertReportTarget({
        workspaceId: params.workspaceId,
        reportedUserId: body.reportedUserId,
        messageId: body.messageId,
      });

      const result = await pool.query<{ id: string }>(
        `INSERT INTO reports (
          workspace_id,reporter_user_id,reported_user_id,message_id,reason
        ) VALUES ($1,$2,$3,$4,$5)
        RETURNING id`,
        [
          params.workspaceId,
          userId,
          body.reportedUserId ?? null,
          body.messageId ?? null,
          body.reason,
        ],
      );

      return reply.code(201).send({ id: result.rows[0]?.id });
    },
  );

  app.get(
    "/workspaces/:workspaceId/moderation/reports",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ workspaceId: z.string().uuid() })
        .parse(request.params);
      const query = z
        .object({
          status: z
            .enum(["open", "reviewing", "resolved", "dismissed"])
            .optional(),
          beforeId: z.string().uuid().optional(),
          limit: z.coerce.number().int().min(1).max(100).default(50),
        })
        .parse(request.query);
      const userId = actor(request);
      await assertModerationPermission(userId, params.workspaceId);

      const values: unknown[] = [params.workspaceId];
      const clauses = ["r.workspace_id=$1"];
      if (query.status) {
        values.push(query.status);
        clauses.push("r.status=$" + values.length);
      }
      if (query.beforeId) {
        values.push(query.beforeId);
        clauses.push(
          `(r.created_at,r.id) < (
            SELECT created_at,id FROM reports WHERE id=$${values.length}
          )`,
        );
      }
      values.push(query.limit + 1);

      const result = await pool.query(
        `SELECT
          r.id,r.reason,r.status,r.created_at,
          r.reporter_user_id,r.reported_user_id,r.message_id,
          reporter.display_name AS reporter_name,
          reported.display_name AS reported_name
         FROM reports r
         JOIN users reporter ON reporter.id=r.reporter_user_id
         LEFT JOIN users reported ON reported.id=r.reported_user_id
         WHERE ${clauses.join(" AND ")}
         ORDER BY r.created_at DESC,r.id DESC
         LIMIT $${values.length}`,
        values,
      );

      const hasMore = result.rows.length > query.limit;
      const items = result.rows.slice(0, query.limit);
      return {
        items,
        nextBeforeId:
          hasMore && items.length > 0
            ? (items[items.length - 1]?.id ?? null)
            : null,
      };
    },
  );

  app.patch(
    "/workspaces/:workspaceId/moderation/reports/:reportId",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          workspaceId: z.string().uuid(),
          reportId: z.string().uuid(),
        })
        .parse(request.params);
      const body = z
        .object({
          status: z.enum(["reviewing", "resolved", "dismissed"]),
        })
        .parse(request.body);
      const userId = actor(request);
      await assertModerationPermission(userId, params.workspaceId);

      const result = await pool.query(
        `UPDATE reports
         SET status=$3
         WHERE id=$1 AND workspace_id=$2
         RETURNING id,status`,
        [params.reportId, params.workspaceId, body.status],
      );
      if (!result.rowCount) {
        throw new AppError(404, "REPORT_NOT_FOUND", "Report not found");
      }

      await recordAudit({
        workspaceId: params.workspaceId,
        actorUserId: userId,
        action: "moderation.report.updated",
        target: { type: "report", id: params.reportId },
        metadata: { status: body.status },
      });

      return result.rows[0];
    },
  );

  app.post(
    "/workspaces/:workspaceId/members/:targetUserId/timeout",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          workspaceId: z.string().uuid(),
          targetUserId: z.string().uuid(),
        })
        .parse(request.params);
      const body = z
        .object({
          until: z.string().datetime(),
          reason: z.string().trim().max(1000).optional(),
        })
        .parse(request.body);
      const userId = actor(request);
      await assertModerationPermission(userId, params.workspaceId);
      await assertWorkspaceTargetMember(
        params.workspaceId,
        params.targetUserId,
      );

      const until = new Date(body.until);
      if (until <= new Date()) {
        throw new AppError(
          400,
          "INVALID_TIMEOUT",
          "Timeout must end in the future",
        );
      }

      await withTransaction(async (client) => {
        await client.query(
          `UPDATE workspace_members
           SET muted_until=$3
           WHERE workspace_id=$1 AND user_id=$2`,
          [params.workspaceId, params.targetUserId, until],
        );
        await client.query(
          `INSERT INTO moderation_actions (
            workspace_id,actor_user_id,target_user_id,action,metadata,expires_at
          ) VALUES ($1,$2,$3,'member.timeout',$4::jsonb,$5)`,
          [
            params.workspaceId,
            userId,
            params.targetUserId,
            JSON.stringify({ reason: body.reason ?? null }),
            until,
          ],
        );
        await recordAudit({
          client,
          workspaceId: params.workspaceId,
          actorUserId: userId,
          action: "member.timeout",
          target: { type: "user", id: params.targetUserId },
          metadata: {
            reason: body.reason ?? null,
            until: until.toISOString(),
          },
        });
      });

      return { ok: true, until: until.toISOString() };
    },
  );

  app.delete(
    "/workspaces/:workspaceId/members/:targetUserId/timeout",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          workspaceId: z.string().uuid(),
          targetUserId: z.string().uuid(),
        })
        .parse(request.params);
      const userId = actor(request);
      await assertModerationPermission(userId, params.workspaceId);

      await pool.query(
        `UPDATE workspace_members
         SET muted_until=NULL
         WHERE workspace_id=$1 AND user_id=$2`,
        [params.workspaceId, params.targetUserId],
      );
      await recordAudit({
        workspaceId: params.workspaceId,
        actorUserId: userId,
        action: "member.timeout.cleared",
        target: { type: "user", id: params.targetUserId },
      });
      return { ok: true };
    },
  );

  app.delete(
    "/workspaces/:workspaceId/members/:targetUserId",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          workspaceId: z.string().uuid(),
          targetUserId: z.string().uuid(),
        })
        .parse(request.params);
      const userId = actor(request);
      await assertModerationPermission(userId, params.workspaceId);

      const workspace = await pool.query<{ owner_user_id: string }>(
        "SELECT owner_user_id FROM workspaces WHERE id=$1",
        [params.workspaceId],
      );
      if (workspace.rows[0]?.owner_user_id === params.targetUserId) {
        throw new AppError(
          409,
          "OWNER_CANNOT_BE_KICKED",
          "Workspace owner cannot be removed",
        );
      }

      const removed = await pool.query(
        `DELETE FROM workspace_members
         WHERE workspace_id=$1 AND user_id=$2`,
        [params.workspaceId, params.targetUserId],
      );
      if (!removed.rowCount) {
        throw new AppError(
          404,
          "WORKSPACE_MEMBER_NOT_FOUND",
          "Workspace member not found",
        );
      }

      await pool.query(
        `INSERT INTO moderation_actions (
          workspace_id,actor_user_id,target_user_id,action
        ) VALUES ($1,$2,$3,'member.kick')`,
        [params.workspaceId, userId, params.targetUserId],
      );
      await recordAudit({
        workspaceId: params.workspaceId,
        actorUserId: userId,
        action: "member.kick",
        target: { type: "user", id: params.targetUserId },
      });
      return { ok: true };
    },
  );

  app.post(
    "/workspaces/:workspaceId/bans/:targetUserId",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          workspaceId: z.string().uuid(),
          targetUserId: z.string().uuid(),
        })
        .parse(request.params);
      const body = z
        .object({
          reason: z.string().trim().max(1000).optional(),
          expiresAt: z.string().datetime().optional(),
        })
        .parse(request.body);
      const userId = actor(request);
      await assertModerationPermission(userId, params.workspaceId);
      await assertWorkspaceTargetMember(
        params.workspaceId,
        params.targetUserId,
      );

      const workspace = await pool.query<{ owner_user_id: string }>(
        "SELECT owner_user_id FROM workspaces WHERE id=$1",
        [params.workspaceId],
      );
      if (workspace.rows[0]?.owner_user_id === params.targetUserId) {
        throw new AppError(
          409,
          "OWNER_CANNOT_BE_BANNED",
          "Workspace owner cannot be banned",
        );
      }

      const expiresAt = body.expiresAt ? new Date(body.expiresAt) : null;
      if (expiresAt && expiresAt <= new Date()) {
        throw new AppError(
          400,
          "INVALID_BAN_EXPIRY",
          "Ban expiry must be in the future",
        );
      }

      await withTransaction(async (client) => {
        await client.query(
          `INSERT INTO workspace_bans (
            workspace_id,user_id,banned_by,reason,expires_at,revoked_at
          ) VALUES ($1,$2,$3,$4,$5,NULL)
          ON CONFLICT (workspace_id,user_id)
          DO UPDATE SET
            banned_by=EXCLUDED.banned_by,
            reason=EXCLUDED.reason,
            expires_at=EXCLUDED.expires_at,
            revoked_at=NULL,
            created_at=now()`,
          [
            params.workspaceId,
            params.targetUserId,
            userId,
            body.reason ?? null,
            expiresAt,
          ],
        );
        await client.query(
          "DELETE FROM workspace_members WHERE workspace_id=$1 AND user_id=$2",
          [params.workspaceId, params.targetUserId],
        );
        await client.query(
          `INSERT INTO moderation_actions (
            workspace_id,actor_user_id,target_user_id,action,metadata,expires_at
          ) VALUES ($1,$2,$3,'member.ban',$4::jsonb,$5)`,
          [
            params.workspaceId,
            userId,
            params.targetUserId,
            JSON.stringify({ reason: body.reason ?? null }),
            expiresAt,
          ],
        );
        await recordAudit({
          client,
          workspaceId: params.workspaceId,
          actorUserId: userId,
          action: "member.ban",
          target: { type: "user", id: params.targetUserId },
          metadata: {
            reason: body.reason ?? null,
            expiresAt: expiresAt?.toISOString() ?? null,
          },
        });
      });

      return { ok: true };
    },
  );

  app.delete(
    "/workspaces/:workspaceId/bans/:targetUserId",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          workspaceId: z.string().uuid(),
          targetUserId: z.string().uuid(),
        })
        .parse(request.params);
      const userId = actor(request);
      await assertModerationPermission(userId, params.workspaceId);

      await pool.query(
        `UPDATE workspace_bans
         SET revoked_at=now()
         WHERE workspace_id=$1 AND user_id=$2 AND revoked_at IS NULL`,
        [params.workspaceId, params.targetUserId],
      );
      await recordAudit({
        workspaceId: params.workspaceId,
        actorUserId: userId,
        action: "member.unban",
        target: { type: "user", id: params.targetUserId },
      });
      return { ok: true };
    },
  );

  app.post(
    "/channels/:channelId/lock",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const userId = actor(request);
      const workspaceId = await channelWorkspaceId(params.channelId);
      await assertModerationPermission(userId, workspaceId);

      await pool.query(
        `UPDATE channels
         SET locked_at=now(),locked_by=$2,updated_at=now()
         WHERE id=$1`,
        [params.channelId, userId],
      );
      await recordAudit({
        workspaceId,
        actorUserId: userId,
        action: "channel.lock",
        target: { type: "channel", id: params.channelId },
      });
      return { ok: true };
    },
  );

  app.delete(
    "/channels/:channelId/lock",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const userId = actor(request);
      const workspaceId = await channelWorkspaceId(params.channelId);
      await assertModerationPermission(userId, workspaceId);

      await pool.query(
        `UPDATE channels
         SET locked_at=NULL,locked_by=NULL,updated_at=now()
         WHERE id=$1`,
        [params.channelId],
      );
      await recordAudit({
        workspaceId,
        actorUserId: userId,
        action: "channel.unlock",
        target: { type: "channel", id: params.channelId },
      });
      return { ok: true };
    },
  );

  app.get(
    "/workspaces/:workspaceId/moderation/rules",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ workspaceId: z.string().uuid() })
        .parse(request.params);
      const userId = actor(request);
      await assertModerationPermission(userId, params.workspaceId);

      const result = await pool.query(
        `SELECT
          max_messages_per_10_seconds AS "maxMessagesPer10Seconds",
          max_mentions_per_message AS "maxMentionsPerMessage",
          repeated_content_window_seconds AS "repeatedContentWindowSeconds",
          repeated_content_limit AS "repeatedContentLimit"
         FROM workspace_moderation_rules
         WHERE workspace_id=$1`,
        [params.workspaceId],
      );

      return (
        result.rows[0] ?? {
          maxMessagesPer10Seconds: 8,
          maxMentionsPerMessage: 12,
          repeatedContentWindowSeconds: 60,
          repeatedContentLimit: 4,
        }
      );
    },
  );

  app.put(
    "/workspaces/:workspaceId/moderation/rules",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ workspaceId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          maxMessagesPer10Seconds: z.number().int().min(1).max(100),
          maxMentionsPerMessage: z.number().int().min(1).max(100),
          repeatedContentWindowSeconds: z.number().int().min(5).max(3600),
          repeatedContentLimit: z.number().int().min(2).max(50),
        })
        .parse(request.body);
      const userId = actor(request);
      await assertModerationPermission(userId, params.workspaceId);

      await pool.query(
        `INSERT INTO workspace_moderation_rules (
          workspace_id,max_messages_per_10_seconds,max_mentions_per_message,
          repeated_content_window_seconds,repeated_content_limit,updated_by,updated_at
        ) VALUES ($1,$2,$3,$4,$5,$6,now())
        ON CONFLICT (workspace_id)
        DO UPDATE SET
          max_messages_per_10_seconds=EXCLUDED.max_messages_per_10_seconds,
          max_mentions_per_message=EXCLUDED.max_mentions_per_message,
          repeated_content_window_seconds=EXCLUDED.repeated_content_window_seconds,
          repeated_content_limit=EXCLUDED.repeated_content_limit,
          updated_by=EXCLUDED.updated_by,
          updated_at=now()`,
        [
          params.workspaceId,
          body.maxMessagesPer10Seconds,
          body.maxMentionsPerMessage,
          body.repeatedContentWindowSeconds,
          body.repeatedContentLimit,
          userId,
        ],
      );

      await invalidateModerationRules(params.workspaceId);
      await recordAudit({
        workspaceId: params.workspaceId,
        actorUserId: userId,
        action: "moderation.rules.updated",
        target: { type: "workspace", id: params.workspaceId },
        metadata: body,
      });

      return { ok: true };
    },
  );
}
