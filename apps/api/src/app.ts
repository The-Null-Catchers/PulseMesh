import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { ZodError } from 'zod';
import { config } from './config.js';
import { AppError } from './errors.js';
import { authenticationPlugin } from './auth/plugin.js';
import { authRoutes } from './auth/routes.js';
import { workspaceRoutes } from './workspaces/routes.js';
import { channelRoutes } from './channels/routes.js';
import { messageRoutes } from './messages/routes.js';
import { messageMutationRoutes } from './messages/mutations.js';
import { messageSyncRoutes } from './messages/sync-routes.js';
import { conversationRoutes } from './conversations/routes.js';
import { readStateRoutes } from './read-states/routes.js';
import { searchRoutes } from './search/routes.js';
import { fileRoutes } from './files/routes.js';
import { notificationRoutes } from './notifications/routes.js';
import { coreMessagingRoutes } from './messages/core-routes.js';
import { channelManagementRoutes } from './channels/management.js';
import { conversationManagementRoutes } from './conversations/management.js';
import { healthRoutes } from './health/routes.js';
import { presenceRoutes } from './presence/routes.js';
import { callRoutes } from './calls/routes.js';
import { redis } from './realtime/bus.js';
import { realtimeTicketRoutes } from './realtime/tickets.js';
import { registerRealtimeGateway } from './realtime/gateway.js';

export async function buildApp() {
  const app = Fastify({
    logger: {
      level:
        config.NODE_ENV === 'production'
          ? 'info'
          : 'debug'
    },
    requestIdHeader: 'x-request-id',
    genReqId: () => randomUUID()
  });

  await app.register(cors, {
    origin: config.WEB_ORIGIN,
    credentials: true
  });

  await app.register(rateLimit, {
    global: true,
    max: 300,
    timeWindow: '1 minute',
    redis
  });

  app.setErrorHandler((error, request, reply) => {
    const appError =
      error instanceof AppError ? error : null;
    const statusCode =
      error instanceof ZodError
        ? 400
        : (appError?.statusCode ?? 500);
    const code =
      error instanceof ZodError
        ? 'VALIDATION_ERROR'
        : (appError?.code ?? 'INTERNAL_ERROR');
    const message =
      error instanceof Error
        ? error.message
        : 'Request failed';

    request.log.error(
      { err: error, code },
      'request failed'
    );

    return reply.code(statusCode).send({
      error: {
        code,
        message:
          statusCode >= 500
            ? 'An unexpected error occurred'
            : message,
        requestId: request.id,
        ...(error instanceof ZodError
          ? {
              details: error.issues.map(
                (issue) => ({
                  path: issue.path,
                  message: issue.message
                })
              )
            }
          : appError?.details
            ? { details: appError.details }
            : {})
      }
    });
  });

  await authenticationPlugin(app);
  await authRoutes(app);
  await workspaceRoutes(app);
  await channelRoutes(app);
  await messageRoutes(app);
  await messageMutationRoutes(app);
  await messageSyncRoutes(app);
  await conversationRoutes(app);
  await readStateRoutes(app);
  await searchRoutes(app);
  await fileRoutes(app);
  await notificationRoutes(app);
  await coreMessagingRoutes(app);
  await channelManagementRoutes(app);
  await conversationManagementRoutes(app);
  await presenceRoutes(app);
  await callRoutes(app);
  await realtimeTicketRoutes(app);
  await registerRealtimeGateway(app);
  await healthRoutes(app);

  return app;
}
