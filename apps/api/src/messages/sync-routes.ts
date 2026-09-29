import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import {
  canAccessChannel,
  canAccessConversation
} from '../authorization/service.js';
import { AppError } from '../errors.js';
import { syncMessageChanges } from './sync-service.js';

const syncQuerySchema = z.object({
  after: z.string().regex(/^\d+$/).default('0'),
  limit: z.coerce.number().int().min(1).max(250).default(100)
});

export async function messageSyncRoutes(
  app: FastifyInstance
): Promise<void> {
  app.get(
    '/channels/:channelId/messages/sync',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const query = syncQuerySchema.parse(request.query);
      const userId = request.auth?.userId;

      if (
        !userId ||
        !(await canAccessChannel(userId, params.channelId))
      ) {
        throw new AppError(
          403,
          'CHANNEL_ACCESS_DENIED',
          'Channel access denied'
        );
      }

      return syncMessageChanges({
        roomKind: 'channel',
        roomId: params.channelId,
        after: query.after,
        limit: query.limit
      });
    }
  );

  app.get(
    '/conversations/:conversationId/messages/sync',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      const query = syncQuerySchema.parse(request.query);
      const userId = request.auth?.userId;

      if (
        !userId ||
        !(await canAccessConversation(
          userId,
          params.conversationId
        ))
      ) {
        throw new AppError(
          403,
          'CONVERSATION_ACCESS_DENIED',
          'Conversation access denied'
        );
      }

      return syncMessageChanges({
        roomKind: 'conversation',
        roomId: params.conversationId,
        after: query.after,
        limit: query.limit
      });
    }
  );
}
