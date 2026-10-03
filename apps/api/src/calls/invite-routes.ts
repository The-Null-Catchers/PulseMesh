import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { RealtimeEvent } from "@pulsemesh/realtime";
import { pool } from "../db/index.js";
import { AppError } from "../errors.js";
import { publishRealtime } from "../realtime/bus.js";
import { canAccessCall, getCallContext } from "./service.js";

type CallInviteRow = {
  call_id: string;
  user_id: string;
  status: "pending" | "accepted" | "declined" | "missed";
  expires_at: Date;
  responded_at: Date | null;
};

function invitePayload(row: CallInviteRow) {
  return {
    callId: row.call_id,
    userId: row.user_id,
    status: row.status,
    expiresAt: row.expires_at.toISOString(),
    respondedAt: row.responded_at?.toISOString() ?? null,
  };
}

async function publishInviteUpdate(row: CallInviteRow): Promise<void> {
  const event: RealtimeEvent = {
    id: randomUUID(),
    type: "call.invite.updated",
    room: "user:" + row.user_id,
    occurredAt: new Date().toISOString(),
    payload: invitePayload(row),
  };
  await publishRealtime(event);
}

async function expireInvite(
  callId: string,
  userId: string,
): Promise<CallInviteRow | null> {
  const expired = await pool.query<CallInviteRow>(
    "UPDATE call_invites SET status='missed',responded_at=COALESCE(responded_at,now()),updated_at=now() WHERE call_id=$1 AND user_id=$2 AND status='pending' AND expires_at<=now() RETURNING call_id,user_id,status,expires_at,responded_at",
    [callId, userId],
  );
  const row = expired.rows[0] ?? null;
  if (row) await publishInviteUpdate(row);
  return row;
}

async function currentInvite(
  callId: string,
  userId: string,
): Promise<CallInviteRow> {
  await expireInvite(callId, userId);
  const result = await pool.query<CallInviteRow>(
    "SELECT call_id,user_id,status,expires_at,responded_at FROM call_invites WHERE call_id=$1 AND user_id=$2",
    [callId, userId],
  );
  const row = result.rows[0];
  if (!row) {
    throw new AppError(404, "CALL_INVITE_NOT_FOUND", "Call invite was not found");
  }
  return row;
}

export async function callInviteRoutes(app: FastifyInstance): Promise<void> {
  app.get(
    "/calls/:callId/invite",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ callId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const context = await getCallContext(params.callId);
      if (
        !context.conversation_id ||
        !(await canAccessCall(userId, context))
      ) {
        throw new AppError(403, "CALL_INVITE_DENIED", "Call invite access denied");
      }

      return invitePayload(await currentInvite(context.id, userId));
    },
  );

  app.post(
    "/calls/:callId/invite/respond",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ callId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({ status: z.enum(["accepted", "declined", "missed"]) })
        .parse(request.body);
      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing user");

      const context = await getCallContext(params.callId);
      if (
        !context.conversation_id ||
        !(await canAccessCall(userId, context))
      ) {
        throw new AppError(403, "CALL_INVITE_DENIED", "Call invite access denied");
      }

      const before = await currentInvite(context.id, userId);
      if (before.status !== "pending") {
        return invitePayload(before);
      }

      if (context.status !== "active" && body.status !== "missed") {
        throw new AppError(409, "CALL_NOT_ACTIVE", "Call is no longer active");
      }

      const result = await pool.query<CallInviteRow>(
        "UPDATE call_invites SET status=$3,responded_at=now(),updated_at=now() WHERE call_id=$1 AND user_id=$2 AND status='pending' RETURNING call_id,user_id,status,expires_at,responded_at",
        [context.id, userId, body.status],
      );
      const row = result.rows[0] ?? (await currentInvite(context.id, userId));
      await publishInviteUpdate(row);
      return invitePayload(row);
    },
  );
}
