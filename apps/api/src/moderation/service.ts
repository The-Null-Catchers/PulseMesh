import { pool } from "../db/index.js";
import {
  assertWorkspacePermission,
  isWorkspaceMember,
} from "../authorization/service.js";
import { AppError } from "../errors.js";

export async function assertModerationPermission(
  userId: string,
  workspaceId: string,
): Promise<void> {
  await assertWorkspacePermission(userId, workspaceId, "moderation.manage");
}

export async function assertWorkspaceTargetMember(
  workspaceId: string,
  targetUserId: string,
): Promise<void> {
  if (!(await isWorkspaceMember(targetUserId, workspaceId))) {
    throw new AppError(
      404,
      "WORKSPACE_MEMBER_NOT_FOUND",
      "Workspace member not found",
    );
  }
}

export async function assertReportTarget(input: {
  workspaceId: string;
  reportedUserId?: string | undefined;
  messageId?: string | undefined;
}): Promise<void> {
  if (!input.reportedUserId && !input.messageId) {
    throw new AppError(
      400,
      "REPORT_TARGET_REQUIRED",
      "A user or message target is required",
    );
  }

  if (input.reportedUserId) {
    await assertWorkspaceTargetMember(input.workspaceId, input.reportedUserId);
  }

  if (input.messageId) {
    const result = await pool.query(
      `SELECT 1
       FROM messages m
       JOIN channels c ON c.id=m.channel_id
       WHERE m.id=$1 AND c.workspace_id=$2
       LIMIT 1`,
      [input.messageId, input.workspaceId],
    );
    if (result.rowCount !== 1) {
      throw new AppError(
        404,
        "REPORT_MESSAGE_NOT_FOUND",
        "Message does not belong to this workspace",
      );
    }
  }
}

export async function channelWorkspaceId(channelId: string): Promise<string> {
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
