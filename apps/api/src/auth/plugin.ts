import type { FastifyInstance, FastifyRequest } from 'fastify';
import { pool } from '../db/index.js';
import { AppError } from '../errors.js';
import { verifyAccessToken } from '../security/tokens.js';

export async function authenticationPlugin(app: FastifyInstance): Promise<void> {
  app.decorateRequest('auth', null);

  app.decorate('authenticate', async (request: FastifyRequest) => {
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new AppError(401, 'AUTH_REQUIRED', 'Authentication required');
    }

    let claims;
    try {
      claims = await verifyAccessToken(header.slice(7));
    } catch {
      throw new AppError(401, 'INVALID_ACCESS_TOKEN', 'Access token is invalid or expired');
    }

    const session = await pool.query(
      'SELECT 1 FROM sessions WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL AND expires_at > now()',
      [claims.sessionId, claims.sub]
    );
    if (session.rowCount !== 1) {
      throw new AppError(401, 'SESSION_REVOKED', 'Session is no longer active');
    }

    request.auth = { userId: claims.sub, sessionId: claims.sessionId };
  });
}
