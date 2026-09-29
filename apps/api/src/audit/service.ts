import type { PoolClient } from 'pg';
import { pool } from '../db/index.js';

type AuditTarget = {
  type?: string | null;
  id?: string | null;
};

export async function recordAudit(input: {
  workspaceId?: string | null;
  actorUserId?: string | null;
  action: string;
  target?: AuditTarget;
  metadata?: Record<string, unknown>;
  client?: PoolClient;
}): Promise<void> {
  const db = input.client ?? pool;
  await db.query(
    `INSERT INTO audit_logs (
      workspace_id,
      actor_user_id,
      action,
      target_type,
      target_id,
      metadata
    ) VALUES ($1,$2,$3,$4,$5,$6::jsonb)`,
    [
      input.workspaceId ?? null,
      input.actorUserId ?? null,
      input.action,
      input.target?.type ?? null,
      input.target?.id ?? null,
      JSON.stringify(input.metadata ?? {})
    ]
  );
}
