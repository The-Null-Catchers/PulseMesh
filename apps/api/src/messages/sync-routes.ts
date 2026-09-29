import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import {
  canAccessChannel,
  canAccessConversation
} from '../authorization/service.js';
import { AppError } from '../errors.js';
import {
  latestMessageSyncCursor,
  syncMessageChanges
} from './sync-service.js';

const syncQuerySchema = z.object({
  after: z.string().regex(/^\d+$/).default('0'),
  limit: z.coerce.number().int().min(1).max(250).default(100)
});

async function assertChannelAccess(
  userId: string | undefined,
  channelId: string
) {
  if (!userId || !(await canAccessChannel(userId, channelId))) {
    throw new AppError(
      403,
      'CHANNEL_ACCESS_DENIED',
      'Channel access denied'
    );
  }
  return userId;
}

async function assertConversationAccess(
  userId: string | undefined,
  conversationId: string
) {
  if (
    !userId ||
    !(await canAccessConversation(userId, conversationId))
  ) {
    throw new AppError(
      403,
      'CONVERSATION_ACCESS_DENIED',
      'Conversation access denied'
    );
  }
  return userId;
}

export async function messageSyncRoutes(
  app: FastifyInstance
): Promise<void> {
  app.get(
    '/channels/:channelId/messages/sync/cursor',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      await assertChannelAccess(
        request.auth?.userId,
        params.channelId
      );

      return {
        cursor: await latestMessageSyncCursor({
          roomKind: 'channel',
          roomId: params.channelId
        })
      };
    }
  );

  app.get(
    '/channels/:channelId/messages/sync',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const query = syncQuerySchema.parse(request.query);
      const userId = await assertChannelAccess(
        request.auth?.userId,
        params.channelId
      );

      return syncMessageChanges({
        roomKind: 'channel',
        roomId: params.channelId,
        userId,
        after: query.after,
        limit: query.limit
      });
    }
  );

  app.get(
    '/conversations/:conversationId/messages/sync/cursor',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      await assertConversationAccess(
        request.auth?.userId,
        params.conversationId
      );

      return {
        cursor: await latestMessageSyncCursor({
          roomKind: 'conversation',
          roomId: params.conversationId
        })
      };
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
      const userId = await assertConversationAccess(
        request.auth?.userId,
        params.conversationId
      );

      return syncMessageChanges({
        roomKind: 'conversation',
        roomId: params.conversationId,
        userId,
        after: query.after,
        limit: query.limit
      });
    }
  );
}
