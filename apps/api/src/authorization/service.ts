import { pool } from '../db/index.js';
import { AppError } from '../errors.js';

export async function hasWorkspacePermission(
  userId: string,
  workspaceId: string,
  permission: string
): Promise<boolean> {
  const result = await pool.query(
    'SELECT 1 FROM workspace_members wm JOIN role_permissions rp ON rp.role_id=wm.role_id JOIN permissions p ON p.id=rp.permission_id WHERE wm.workspace_id=$1 AND wm.user_id=$2 AND p.key=$3 LIMIT 1',
    [workspaceId, userId, permission]
  );
  return result.rowCount === 1;
}

export async function assertWorkspacePermission(
  userId: string,
  workspaceId: string,
  permission: string
): Promise<void> {
  if (!(await hasWorkspacePermission(userId, workspaceId, permission))) {
    throw new AppError(
      403,
      'PERMISSION_DENIED',
      'You do not have permission for this action'
    );
  }
}

export async function isWorkspaceMember(
  userId: string,
  workspaceId: string
): Promise<boolean> {
  const result = await pool.query(
    'SELECT 1 FROM workspace_members WHERE workspace_id=$1 AND user_id=$2',
    [workspaceId, userId]
  );
  return result.rowCount === 1;
}

export async function isWorkspaceBanned(
  userId: string,
  workspaceId: string
): Promise<boolean> {
  const result = await pool.query(
    `SELECT 1
     FROM workspace_bans
     WHERE workspace_id=$1
       AND user_id=$2
       AND revoked_at IS NULL
       AND (expires_at IS NULL OR expires_at>now())
     LIMIT 1`,
    [workspaceId, userId]
  );
  return result.rowCount === 1;
}

export async function canAccessChannel(
  userId: string,
  channelId: string
): Promise<boolean> {
  const result = await pool.query(
    `SELECT 1
     FROM channels c
     JOIN workspace_members wm ON wm.workspace_id=c.workspace_id
     LEFT JOIN channel_members cm
       ON cm.channel_id=c.id AND cm.user_id=wm.user_id
     WHERE c.id=$1
       AND wm.user_id=$2
       AND (c.visibility <> 'private' OR cm.user_id IS NOT NULL)
     LIMIT 1`,
    [channelId, userId]
  );
  return result.rowCount === 1;
}

export async function canSendToChannel(
  userId: string,
  channelId: string
): Promise<boolean> {
  const result = await pool.query(
    `SELECT 1
     FROM channels c
     JOIN workspace_members wm ON wm.workspace_id=c.workspace_id
     JOIN role_permissions rp ON rp.role_id=wm.role_id
     JOIN permissions p ON p.id=rp.permission_id
     LEFT JOIN channel_members cm
       ON cm.channel_id=c.id AND cm.user_id=wm.user_id
     WHERE c.id=$1
       AND wm.user_id=$2
       AND c.kind='text'
       AND c.archived_at IS NULL
       AND c.locked_at IS NULL
       AND (wm.muted_until IS NULL OR wm.muted_until<=now())
       AND c.visibility NOT IN ('read-only','announcement')
       AND p.key='message.send'
       AND (c.visibility <> 'private' OR cm.user_id IS NOT NULL)
     LIMIT 1`,
    [channelId, userId]
  );
  return result.rowCount === 1;
}

export async function canAccessConversation(
  userId: string,
  conversationId: string
): Promise<boolean> {
  const result = await pool.query(
    'SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2',
    [conversationId, userId]
  );
  return result.rowCount === 1;
}
