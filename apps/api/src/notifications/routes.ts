import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import {
  canAccessChannel,
  canAccessConversation,
  isWorkspaceMember
} from '../authorization/service.js';
import { config } from '../config.js';
import { pool, withTransaction } from '../db/index.js';
import { AppError } from '../errors.js';

const quietHoursSchema = z
  .object({
    start: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
    end: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
    timezone: z.string().min(1).max(100)
  })
  .nullable();

export async function notificationRoutes(
  app: FastifyInstance
): Promise<void> {
  app.get(
    '/notifications',
    { preHandler: app.authenticate },
    async (request) => {
      const result = await pool.query(
        'SELECT id,kind,payload,read_at,delivered_at,created_at FROM notifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100',
        [request.auth?.userId]
      );
      return { items: result.rows };
    }
  );

  app.post(
    '/notifications/:notificationId/read',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ notificationId: z.string().uuid() })
        .parse(request.params);
      await pool.query(
        'UPDATE notifications SET read_at=COALESCE(read_at,now()) WHERE id=$1 AND user_id=$2',
        [params.notificationId, request.auth?.userId]
      );
      return { ok: true };
    }
  );

  app.post(
    '/notifications/read-all',
    { preHandler: app.authenticate },
    async (request) => {
      await pool.query(
        'UPDATE notifications SET read_at=COALESCE(read_at,now()) WHERE user_id=$1 AND read_at IS NULL',
        [request.auth?.userId]
      );
      return { ok: true };
    }
  );

  app.get(
    '/notification-preferences',
    { preHandler: app.authenticate },
    async (request) => {
      const result = await pool.query(
        'SELECT id,workspace_id,channel_id,conversation_id,level,quiet_hours FROM notification_preferences WHERE user_id=$1 ORDER BY id',
        [request.auth?.userId]
      );
      return { items: result.rows };
    }
  );

  app.put(
    '/notification-preferences',
    { preHandler: app.authenticate },
    async (request) => {
      const body = z
        .object({
          workspaceId: z.string().uuid().optional(),
          channelId: z.string().uuid().optional(),
          conversationId: z.string().uuid().optional(),
          level: z.enum(['all', 'mentions', 'nothing']),
          quietHours: quietHoursSchema.optional().default(null)
        })
        .refine(
          (value) =>
            [
              value.workspaceId,
              value.channelId,
              value.conversationId
            ].filter(Boolean).length <= 1,
          { message: 'Only one preference scope can be set at a time' }
        )
        .parse(request.body);

      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      if (
        body.workspaceId &&
        !(await isWorkspaceMember(userId, body.workspaceId))
      ) {
        throw new AppError(
          403,
          'NOTIFICATION_SCOPE_DENIED',
          'Workspace access denied'
        );
      }
      if (
        body.channelId &&
        !(await canAccessChannel(userId, body.channelId))
      ) {
        throw new AppError(
          403,
          'NOTIFICATION_SCOPE_DENIED',
          'Channel access denied'
        );
      }
      if (
        body.conversationId &&
        !(await canAccessConversation(userId, body.conversationId))
      ) {
        throw new AppError(
          403,
          'NOTIFICATION_SCOPE_DENIED',
          'Conversation access denied'
        );
      }

      await withTransaction(async (client) => {
        await client.query(
          'DELETE FROM notification_preferences WHERE user_id=$1 AND workspace_id IS NOT DISTINCT FROM $2::uuid AND channel_id IS NOT DISTINCT FROM $3::uuid AND conversation_id IS NOT DISTINCT FROM $4::uuid',
          [
            userId,
            body.workspaceId ?? null,
            body.channelId ?? null,
            body.conversationId ?? null
          ]
        );
        await client.query(
          'INSERT INTO notification_preferences (user_id,workspace_id,channel_id,conversation_id,level,quiet_hours) VALUES ($1,$2,$3,$4,$5,$6::jsonb)',
          [
            userId,
            body.workspaceId ?? null,
            body.channelId ?? null,
            body.conversationId ?? null,
            body.level,
            body.quietHours
              ? JSON.stringify(body.quietHours)
              : null
          ]
        );
      });

      return { ok: true };
    }
  );

  app.get(
    '/notification-devices',
    { preHandler: app.authenticate },
    async (request) => {
      const [mobile, web] = await Promise.all([
        pool.query(
          'SELECT id,platform,enabled,last_seen_at,created_at FROM notification_devices WHERE user_id=$1 ORDER BY last_seen_at DESC',
          [request.auth?.userId]
        ),
        pool.query(
          'SELECT id,endpoint,enabled,last_seen_at,created_at FROM web_push_subscriptions WHERE user_id=$1 ORDER BY last_seen_at DESC',
          [request.auth?.userId]
        )
      ]);

      return {
        mobile: mobile.rows,
        web: web.rows.map((row) => ({
          ...row,
          endpoint: String(row.endpoint).replace(/^(https?:\/\/[^/]+).*/, '$1')
        }))
      };
    }
  );

  app.post(
    '/notification-devices',
    { preHandler: app.authenticate },
    async (request, reply) => {
      const body = z
        .object({
          platform: z.enum(['android', 'ios']),
          token: z.string().min(20).max(4096)
        })
        .parse(request.body);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const result = await pool.query<{ id: string }>(
        'INSERT INTO notification_devices (user_id,platform,fcm_token) VALUES ($1,$2,$3) ON CONFLICT (fcm_token) DO UPDATE SET user_id=EXCLUDED.user_id,platform=EXCLUDED.platform,enabled=true,last_seen_at=now() RETURNING id',
        [userId, body.platform, body.token]
      );

      return reply.code(201).send({ id: result.rows[0]?.id });
    }
  );

  app.delete(
    '/notification-devices/:deviceId',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ deviceId: z.string().uuid() })
        .parse(request.params);
      await pool.query(
        'DELETE FROM notification_devices WHERE id=$1 AND user_id=$2',
        [params.deviceId, request.auth?.userId]
      );
      return { ok: true };
    }
  );

  app.get('/web-push/config', async () => ({
    publicKey: config.WEB_PUSH_PUBLIC_KEY || null
  }));

  app.post(
    '/web-push/subscriptions',
    { preHandler: app.authenticate },
    async (request, reply) => {
      const body = z
        .object({
          endpoint: z.string().url().max(4096),
          keys: z.object({
            p256dh: z.string().min(20).max(4096),
            auth: z.string().min(8).max(1024)
          })
        })
        .parse(request.body);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const result = await pool.query<{ id: string }>(
        'INSERT INTO web_push_subscriptions (user_id,endpoint,p256dh,auth) VALUES ($1,$2,$3,$4) ON CONFLICT (endpoint) DO UPDATE SET user_id=EXCLUDED.user_id,p256dh=EXCLUDED.p256dh,auth=EXCLUDED.auth,enabled=true,last_seen_at=now() RETURNING id',
        [userId, body.endpoint, body.keys.p256dh, body.keys.auth]
      );

      return reply.code(201).send({ id: result.rows[0]?.id });
    }
  );

  app.delete(
    '/web-push/subscriptions/:subscriptionId',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ subscriptionId: z.string().uuid() })
        .parse(request.params);
      await pool.query(
        'DELETE FROM web_push_subscriptions WHERE id=$1 AND user_id=$2',
        [params.subscriptionId, request.auth?.userId]
      );
      return { ok: true };
    }
  );
}
