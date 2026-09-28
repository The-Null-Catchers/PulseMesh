import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/index.js';

export async function notificationRoutes(app: FastifyInstance): Promise<void> {
  app.get('/notifications', { preHandler: app.authenticate }, async (request) => {
    const result = await pool.query(
      'SELECT id,kind,payload,read_at,created_at FROM notifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100',
      [request.auth?.userId]
    );
    return { items: result.rows };
  });

  app.post('/notifications/:notificationId/read', { preHandler: app.authenticate }, async (request) => {
    const params = z.object({ notificationId: z.string().uuid() }).parse(request.params);
    await pool.query(
      'UPDATE notifications SET read_at=COALESCE(read_at,now()) WHERE id=$1 AND user_id=$2',
      [params.notificationId, request.auth?.userId]
    );
    return { ok: true };
  });

  app.put('/notification-preferences', { preHandler: app.authenticate }, async (request) => {
    const body = z.object({
      workspaceId: z.string().uuid().optional(),
      channelId: z.string().uuid().optional(),
      conversationId: z.string().uuid().optional(),
      level: z.enum(['all','mentions','nothing'])
    }).parse(request.body);
    await pool.query(
      'INSERT INTO notification_preferences (user_id,workspace_id,channel_id,conversation_id,level) VALUES ($1,$2,$3,$4,$5)',
      [request.auth?.userId, body.workspaceId ?? null, body.channelId ?? null, body.conversationId ?? null, body.level]
    );
    return { ok: true };
  });
}
