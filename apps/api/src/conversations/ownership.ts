import type { PoolClient } from "pg";
import { AppError } from "../errors.js";

/** Caller must hold a transaction for the entire transfer. */
export async function transferGroupOwnership(
  client: PoolClient,
  conversationId: string,
  actorId: string,
  targetId: string,
): Promise<void> {
  // Serialize transfers before checking authority, so a waiting old owner
  // cannot authorize another transfer using a role read before the first commit.
  const group = await client.query<{ owner_user_id: string }>(
    "SELECT owner_user_id FROM conversations WHERE id=$1 AND kind='group' FOR UPDATE",
    [conversationId],
  );
  if (group.rows[0]?.owner_user_id !== actorId) {
    throw new AppError(
      403,
      "CONVERSATION_OWNER_REQUIRED",
      "Only the owner can transfer group ownership",
    );
  }
  if (targetId === actorId) {
    throw new AppError(
      400,
      "OWNER_TRANSFER_TARGET_INVALID",
      "Choose another group member as the new owner",
    );
  }
  // Keep membership stable until both roles and the owning conversation commit.
  const members = await client.query<{ user_id: string; role: string }>(
    "SELECT user_id,role FROM conversation_members WHERE conversation_id=$1 AND user_id=ANY($2::uuid[]) ORDER BY user_id FOR UPDATE",
    [conversationId, [actorId, targetId]],
  );
  if (
    !members.rows.some(
      (member) => member.user_id === actorId && member.role === "owner",
    )
  ) {
    throw new AppError(
      403,
      "CONVERSATION_OWNER_REQUIRED",
      "Only the owner can transfer group ownership",
    );
  }
  if (!members.rows.some((member) => member.user_id === targetId)) {
    throw new AppError(
      404,
      "MEMBER_NOT_FOUND",
      "New owner must already be a group member",
    );
  }
  await client.query(
    "UPDATE conversation_members SET role=CASE WHEN user_id=$2 THEN 'owner' ELSE 'member' END WHERE conversation_id=$1 AND user_id=ANY($3::uuid[])",
    [conversationId, targetId, [actorId, targetId]],
  );
  await client.query(
    "UPDATE conversations SET owner_user_id=$1,updated_at=now() WHERE id=$2",
    [targetId, conversationId],
  );
}
