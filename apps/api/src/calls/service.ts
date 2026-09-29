import {
  canAccessChannel,
  canAccessConversation,
} from "../authorization/service.js";
import { pool } from "../db/index.js";
import { AppError } from "../errors.js";

export interface CallContext {
  id: string;
  channel_id: string | null;
  conversation_id: string | null;
  created_by: string;
  kind: "voice" | "video";
  status: string;
  provider: string;
  started_at: Date;
  ended_at: Date | null;
  workspace_id: string | null;
}

export interface ActiveCallParticipant {
  id: string;
  call_id: string;
  user_id: string;
  session_id: string | null;
  muted: boolean;
  deafened: boolean;
  camera_enabled: boolean;
  screen_sharing: boolean;
  connection_state: string;
  joined_at: Date;
}

export async function getCallContext(callId: string): Promise<CallContext> {
  const result = await pool.query<CallContext>(
    "SELECT ca.id,ca.channel_id,ca.conversation_id,ca.created_by,ca.kind,ca.status,ca.provider,ca.started_at,ca.ended_at,c.workspace_id FROM calls ca LEFT JOIN channels c ON c.id=ca.channel_id WHERE ca.id=$1",
    [callId],
  );
  const call = result.rows[0];
  if (!call) {
    throw new AppError(404, "CALL_NOT_FOUND", "Call not found");
  }
  return call;
}

export function callDestinationRoom(call: {
  channel_id: string | null;
  conversation_id: string | null;
}): string {
  if (call.channel_id) return "channel:" + call.channel_id;
  if (call.conversation_id) {
    return "conversation:" + call.conversation_id;
  }
  throw new Error("Call has no destination");
}

export async function canAccessCall(
  userId: string,
  call: CallContext,
): Promise<boolean> {
  if (call.channel_id) {
    return canAccessChannel(userId, call.channel_id);
  }
  if (call.conversation_id) {
    return canAccessConversation(userId, call.conversation_id);
  }
  return false;
}

export async function activeParticipantForSession(
  callId: string,
  userId: string,
  sessionId: string,
): Promise<ActiveCallParticipant | null> {
  const result = await pool.query<ActiveCallParticipant>(
    "SELECT p.id,p.call_id,p.user_id,p.session_id,p.muted,p.deafened,p.camera_enabled,p.screen_sharing,p.connection_state,p.joined_at FROM call_participants p JOIN calls c ON c.id=p.call_id WHERE p.call_id=$1 AND p.user_id=$2 AND p.session_id=$3 AND p.left_at IS NULL AND c.status='active' LIMIT 1",
    [callId, userId, sessionId],
  );
  return result.rows[0] ?? null;
}

export async function activeParticipantById(
  callId: string,
  participantId: string,
): Promise<ActiveCallParticipant | null> {
  const result = await pool.query<ActiveCallParticipant>(
    "SELECT p.id,p.call_id,p.user_id,p.session_id,p.muted,p.deafened,p.camera_enabled,p.screen_sharing,p.connection_state,p.joined_at FROM call_participants p JOIN calls c ON c.id=p.call_id WHERE p.call_id=$1 AND p.id=$2 AND p.left_at IS NULL AND c.status='active' LIMIT 1",
    [callId, participantId],
  );
  return result.rows[0] ?? null;
}

export async function signalingContext(input: {
  callId: string;
  userId: string;
  sessionId: string;
  targetParticipantId: string;
}): Promise<{
  sender: ActiveCallParticipant;
  target: ActiveCallParticipant;
}> {
  const [sender, target] = await Promise.all([
    activeParticipantForSession(input.callId, input.userId, input.sessionId),
    activeParticipantById(input.callId, input.targetParticipantId),
  ]);

  if (!sender) {
    throw new AppError(
      403,
      "CALL_PARTICIPANT_REQUIRED",
      "Join the call before signaling",
    );
  }
  if (!target?.session_id) {
    throw new AppError(
      404,
      "CALL_TARGET_NOT_FOUND",
      "Target participant is not active",
    );
  }

  return { sender, target };
}
