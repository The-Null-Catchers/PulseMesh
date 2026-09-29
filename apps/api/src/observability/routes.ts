import { timingSafeEqual } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { config } from '../config.js';
import { AppError } from '../errors.js';
import { metricsRegistry } from './metrics.js';

function tokenMatches(header: string | undefined): boolean {
  if (!config.METRICS_TOKEN) return true;
  if (!header?.startsWith('Bearer ')) return false;

  const provided = Buffer.from(header.slice(7));
  const expected = Buffer.from(config.METRICS_TOKEN);
  return (
    provided.length === expected.length &&
    timingSafeEqual(provided, expected)
  );
}

export async function observabilityRoutes(
  app: FastifyInstance
): Promise<void> {
  app.get('/metrics', async (request, reply) => {
    if (!tokenMatches(request.headers.authorization)) {
      throw new AppError(
        401,
        'METRICS_UNAUTHORIZED',
        'Metrics authentication required'
      );
    }

    const body = await metricsRegistry.metrics();
    return reply
      .header('content-type', metricsRegistry.contentType)
      .send(body);
  });
}
