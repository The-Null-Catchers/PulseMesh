import type { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { RealtimeEvent } from '@pulsemesh/realtime';
import { pool } from '../db/index.js';
import { assertWorkspacePermission, isWorkspaceMember } from '../authorization/service.js';
import { publishRealtime } from '../realtime/bus.js';
import { AppError } from '../errors.js';

export async function channelRoutes(app: FastifyInstance): Promise<void> {
  app.get('/workspaces/:workspaceId/channels', { preHandler: app.authenticate }, async (request) => {
    const params = z.object({ workspaceId: z.string().uuid() }).parse(request.params);
    const userId = request.auth?.userId;
    if (!userId || !(await isWorkspaceMember(userId, params.workspaceId))) {
      throw new AppError(403, 'WORKSPACE_ACCESS_DENIED', 'Workspace access denied');
    }
    const result = await pool.query(
      `SELECT c.id,c.name,c.topic,c.kind,c.visibility,c.position,c.archived_at
       FROM channels c
       LEFT JOIN channel_members cm
         ON cm.channel_id=c.id AND cm.user_id=$2
       WHERE c.workspace_id=$1
         AND c.archived_at IS NULL
         AND (c.visibility<>'private' OR cm.user_id IS NOT NULL)
       ORDER BY c.position,c.name`,
      [params.workspaceId, userId]
    );
    return { items: result.rows };
  });

  app.post('/workspaces/:workspaceId/channels', {
    preHandler: app.authenticate,
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const params = z.object({ workspaceId: z.string().uuid() }).parse(request.params);
    const body = z.object({
      name: z.string().min(1).max(80).regex(/^[a-z0-9-]+$/),
      kind: z.enum(['text', 'voice']).default('text'),
      visibility: z.enum(['public', 'private', 'read-only', 'announcement']).default('public')
    }).parse(request.body);
    const userId = request.auth?.userId;
    if (!userId) throw new Error('Missing user');
    await assertWorkspacePermission(userId, params.workspaceId, 'channel.create');

    const result = await pool.query<{ id: string; workspace_id: string }>(
      'INSERT INTO channels (workspace_id,name,kind,visibility,position,created_by) VALUES ($1,$2,$3,$4,(SELECT COALESCE(MAX(position),-1)+1 FROM channels WHERE workspace_id=$1),$5) RETURNING id,workspace_id',
      [params.workspaceId, body.name, body.kind, body.visibility, userId]
    );
    const channel = result.rows[0];
    if (!channel) throw new Error('Channel creation failed');

    const event: RealtimeEvent = {
      id: randomUUID(),
      type: 'channel.created',
      room: 'workspace:' + params.workspaceId,
      occurredAt: new Date().toISOString(),
      payload: { channelId: channel.id, workspaceId: channel.workspace_id }
    };
    await publishRealtime(event);
    return reply.code(201).send(channel);
  });
}
