import { randomUUID } from 'node:crypto';
import type { RealtimeEvent } from '@pulsemesh/realtime';
import { pool } from '../db/index.js';
import { publishRealtime, redis } from '../realtime/bus.js';

export type PresenceStatus = 'online' | 'idle' | 'do-not-disturb' | 'offline';

export interface PresenceSnapshot {
  userId: string;
  status: PresenceStatus;
  customText: string | null;
  lastSeenAt: string | null;
  connectedDevices: number;
  activeWorkspaceId: string | null;
}

const PRESENCE_TTL_SECONDS = 70;
const PRESENCE_INDEX_KEY = 'presence:users:expiry';

function sessionsKey(userId: string): string {
  return 'presence:user:' + userId + ':sessions';
}

function activeWorkspaceKey(userId: string): string {
  return 'presence:user:' + userId + ':active-workspace';
}

async function syncExpiryIndex(userId: string): Promise<void> {
  const latest = await redis.zrevrange(sessionsKey(userId), 0, 0, 'WITHSCORES');
  const score = latest[1];
  if (!score) {
    await redis.zrem(PRESENCE_INDEX_KEY, userId);
    return;
  }
  await redis.zadd(PRESENCE_INDEX_KEY, Number(score), userId);
}

export async function touchPresence(userId: string, sessionId: string): Promise<boolean> {
  const now = Date.now();
  const expiresAt = now + PRESENCE_TTL_SECONDS * 1000;
  const script = [
    "redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[1])",
    "local before = redis.call('ZCARD', KEYS[1])",
    "redis.call('ZADD', KEYS[1], ARGV[2], ARGV[3])",
    "redis.call('EXPIRE', KEYS[1], ARGV[4])",
    "return before"
  ].join('\n');

  const before = Number(
    await redis.eval(
      script,
      1,
      sessionsKey(userId),
      now,
      expiresAt,
      sessionId,
      PRESENCE_TTL_SECONDS * 2
    )
  );

  await redis.expire(activeWorkspaceKey(userId), PRESENCE_TTL_SECONDS * 2);
  await syncExpiryIndex(userId);
  return before === 0;
}

export async function disconnectPresence(userId: string, sessionId: string): Promise<boolean> {
  const key = sessionsKey(userId);
  const before = await redis.zcard(key);
  await redis.zrem(key, sessionId);
  await redis.zremrangebyscore(key, '-inf', Date.now());
  const remaining = await redis.zcard(key);

  if (remaining === 0) {
    await redis.del(key);
    await redis.zrem(PRESENCE_INDEX_KEY, userId);
    if (before > 0) {
      await pool.query('UPDATE users SET last_seen_at=now() WHERE id=$1', [userId]);
      return true;
    }
    return false;
  }

  await syncExpiryIndex(userId);
  return false;
}

export async function currentPresence(userId: string): Promise<PresenceSnapshot> {
  await redis.zremrangebyscore(sessionsKey(userId), '-inf', Date.now());
  const [profile, connectedDevices, activeWorkspaceId] = await Promise.all([
    pool.query<{
      presence_mode: 'online' | 'idle' | 'do-not-disturb';
      status_text: string | null;
      last_seen_at: Date | null;
    }>(
      'SELECT presence_mode,status_text,last_seen_at FROM users WHERE id=$1',
      [userId]
    ),
    redis.zcard(sessionsKey(userId)),
    redis.get(activeWorkspaceKey(userId))
  ]);

  const row = profile.rows[0];
  if (!row) throw new Error('Presence user not found');

  return {
    userId,
    status: connectedDevices > 0 ? row.presence_mode : 'offline',
    customText: row.status_text,
    lastSeenAt: row.last_seen_at?.toISOString() ?? null,
    connectedDevices,
    activeWorkspaceId
  };
}

export async function updatePresenceSettings(input: {
  userId: string;
  status: 'online' | 'idle' | 'do-not-disturb';
  customText: string | null;
  activeWorkspaceId?: string | null;
}): Promise<PresenceSnapshot> {
  await pool.query(
    'UPDATE users SET presence_mode=$2,status_text=$3,updated_at=now() WHERE id=$1',
    [input.userId, input.status, input.customText]
  );

  if (input.activeWorkspaceId !== undefined) {
    if (input.activeWorkspaceId === null) {
      await redis.del(activeWorkspaceKey(input.userId));
    } else {
      await redis.set(
        activeWorkspaceKey(input.userId),
        input.activeWorkspaceId,
        'EX',
        PRESENCE_TTL_SECONDS * 2
      );
    }
  }

  return currentPresence(input.userId);
}

export async function broadcastPresence(userId: string): Promise<void> {
  const [snapshot, memberships] = await Promise.all([
    currentPresence(userId),
    pool.query<{ workspace_id: string }>(
      'SELECT workspace_id FROM workspace_members WHERE user_id=$1',
      [userId]
    )
  ]);

  for (const membership of memberships.rows) {
    const event: RealtimeEvent = {
      id: randomUUID(),
      type: 'presence.updated',
      room: 'workspace:' + membership.workspace_id,
      occurredAt: new Date().toISOString(),
      payload: snapshot
    };
    await publishRealtime(event);
  }
}

export async function sweepExpiredPresence(): Promise<number> {
  const now = Date.now();
  const userIds = await redis.zrangebyscore(
    PRESENCE_INDEX_KEY,
    '-inf',
    now,
    'LIMIT',
    0,
    200
  );

  let offlineTransitions = 0;
  for (const userId of userIds) {
    const key = sessionsKey(userId);
    await redis.zremrangebyscore(key, '-inf', now);
    const remaining = await redis.zcard(key);

    if (remaining > 0) {
      await syncExpiryIndex(userId);
      continue;
    }

    const removed = await redis.zrem(PRESENCE_INDEX_KEY, userId);
    await redis.del(key);
    if (removed === 0) continue;

    await pool.query('UPDATE users SET last_seen_at=now() WHERE id=$1', [userId]);
    await broadcastPresence(userId);
    offlineTransitions += 1;
  }

  return offlineTransitions;
}

function pipelineValue(
  results: Array<[Error | null, unknown]> | null,
  index: number
): unknown {
  return results?.[index]?.[1];
}

export async function listWorkspacePresence(
  workspaceId: string
): Promise<PresenceSnapshot[]> {
  const members = await pool.query<{
    id: string;
    presence_mode: 'online' | 'idle' | 'do-not-disturb';
    status_text: string | null;
    last_seen_at: Date | null;
  }>(
    'SELECT u.id,u.presence_mode,u.status_text,u.last_seen_at FROM workspace_members wm JOIN users u ON u.id=wm.user_id WHERE wm.workspace_id=$1 ORDER BY u.display_name,u.id',
    [workspaceId]
  );

  const now = Date.now();
  const pipeline = redis.pipeline();
  for (const member of members.rows) {
    pipeline.zremrangebyscore(sessionsKey(member.id), '-inf', now);
    pipeline.zcard(sessionsKey(member.id));
    pipeline.get(activeWorkspaceKey(member.id));
  }
  const results = await pipeline.exec();

  return members.rows.map((member, index) => {
    const base = index * 3;
    const connectedDevices = Number(pipelineValue(results, base + 1) ?? 0);
    const activeWorkspace = pipelineValue(results, base + 2);
    return {
      userId: member.id,
      status: connectedDevices > 0 ? member.presence_mode : 'offline',
      customText: member.status_text,
      lastSeenAt: member.last_seen_at?.toISOString() ?? null,
      connectedDevices,
      activeWorkspaceId: typeof activeWorkspace === 'string' ? activeWorkspace : null
    };
  });
}
