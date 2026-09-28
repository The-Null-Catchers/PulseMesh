import { Queue } from 'bullmq';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { randomToken, sha256 } from '@pulsemesh/shared';
import { config } from '../config.js';
import { pool, withTransaction } from '../db/index.js';
import { AppError } from '../errors.js';
import { queueRedis } from '../realtime/bus.js';
import { hashPassword, verifyPassword } from '../security/passwords.js';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from '../security/tokens.js';

const notificationQueue = new Queue('notifications', { connection: queueRedis });

const credentialsSchema = z.object({
  email: z.string().email().transform((value) => value.toLowerCase()),
  password: z.string().min(12).max(128)
});

const registerSchema = credentialsSchema.extend({
  username: z.string().min(3).max(32).regex(/^[a-zA-Z0-9_.-]+$/),
  displayName: z.string().min(1).max(80),
  device: z.string().max(100).optional(),
  browser: z.string().max(100).optional(),
  os: z.string().max(100).optional()
});

const loginSchema = credentialsSchema.extend({
  device: z.string().max(100).optional(),
  browser: z.string().max(100).optional(),
  os: z.string().max(100).optional()
});

async function issueSession(
  userId: string,
  meta: { device?: string; browser?: string; os?: string },
  request: { ip: string; headers: { 'user-agent'?: string } }
) {
  return withTransaction(async (client) => {
    const result = await client.query<{ id: string; family_id: string }>(
      'INSERT INTO sessions (user_id,refresh_token_hash,device,browser,os,ip,user_agent,expires_at) VALUES ($1,$2,$3,$4,$5,$6,$7,now()+($8 || \' seconds\')::interval) RETURNING id,family_id',
      [
        userId,
        'pending',
        meta.device ?? null,
        meta.browser ?? null,
        meta.os ?? null,
        request.ip,
        request.headers['user-agent'] ?? null,
        String(config.REFRESH_TOKEN_TTL_SECONDS)
      ]
    );
    const session = result.rows[0];
    if (!session) throw new Error('Session creation failed');

    const refreshToken = await signRefreshToken({
      sub: userId,
      sessionId: session.id,
      generation: 0,
      familyId: session.family_id
    });
    await client.query('UPDATE sessions SET refresh_token_hash=$1 WHERE id=$2', [
      sha256(refreshToken),
      session.id
    ]);

    const accessToken = await signAccessToken({ sub: userId, sessionId: session.id });
    return { accessToken, refreshToken };
  });
}

export async function authRoutes(app: FastifyInstance): Promise<void> {
  app.post('/auth/register', {
    config: { rateLimit: { max: 8, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const body = registerSchema.parse(request.body);
    const passwordHash = await hashPassword(body.password);

    const created = await withTransaction(async (client) => {
      const exists = await client.query('SELECT 1 FROM users WHERE email=$1 OR username=$2', [
        body.email,
        body.username.toLowerCase()
      ]);
      if (exists.rowCount) {
        throw new AppError(409, 'ACCOUNT_EXISTS', 'Email or username is already in use');
      }

      const result = await client.query<{ id: string }>(
        'INSERT INTO users (email,username,display_name,password_hash) VALUES ($1,$2,$3,$4) RETURNING id',
        [body.email, body.username.toLowerCase(), body.displayName, passwordHash]
      );
      const user = result.rows[0];
      if (!user) throw new Error('User creation failed');

      const verificationToken = randomToken();
      await client.query(
        'INSERT INTO email_verification_tokens (user_id,token_hash,expires_at) VALUES ($1,$2,now()+interval \'24 hours\')',
        [user.id, sha256(verificationToken)]
      );
      await notificationQueue.add('email.verify', {
        userId: user.id,
        email: body.email,
        token: verificationToken
      });
      return user;
    });

    const tokens = await issueSession(created.id, body, request);
    return reply.code(201).send(tokens);
  });

  app.post('/auth/login', {
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } }
  }, async (request) => {
    const body = loginSchema.parse(request.body);
    const result = await pool.query<{ id: string; password_hash: string }>(
      'SELECT id,password_hash FROM users WHERE email=$1',
      [body.email]
    );
    const user = result.rows[0];
    if (!user || !(await verifyPassword(user.password_hash, body.password))) {
      throw new AppError(401, 'INVALID_CREDENTIALS', 'Email or password is incorrect');
    }
    return issueSession(user.id, body, request);
  });

  app.post('/auth/refresh', async (request) => {
    const body = z.object({ refreshToken: z.string().min(20) }).parse(request.body);
    let claims;
    try {
      claims = await verifyRefreshToken(body.refreshToken);
    } catch {
      throw new AppError(401, 'INVALID_REFRESH_TOKEN', 'Refresh token is invalid');
    }

    const rotated = await withTransaction(async (client) => {
      const result = await client.query<{
        id: string;
        user_id: string;
        family_id: string;
        refresh_token_hash: string;
        generation: number;
        revoked_at: Date | null;
      }>(
        'SELECT id,user_id,family_id,refresh_token_hash,generation,revoked_at FROM sessions WHERE id=$1 FOR UPDATE',
        [claims.sessionId]
      );
      const session = result.rows[0];
      const invalid =
        !session ||
        session.revoked_at !== null ||
        session.user_id !== claims.sub ||
        session.family_id !== claims.familyId ||
        session.generation !== claims.generation ||
        session.refresh_token_hash !== sha256(body.refreshToken);

      if (invalid) {
        await client.query(
          'UPDATE sessions SET revoked_at=COALESCE(revoked_at,now()) WHERE family_id=$1',
          [claims.familyId]
        );
        return null;
      }

      const generation = session.generation + 1;
      const refreshToken = await signRefreshToken({
        sub: session.user_id,
        sessionId: session.id,
        generation,
        familyId: session.family_id
      });
      await client.query(
        'UPDATE sessions SET generation=$1,refresh_token_hash=$2,last_active_at=now() WHERE id=$3',
        [generation, sha256(refreshToken), session.id]
      );
      const accessToken = await signAccessToken({
        sub: session.user_id,
        sessionId: session.id
      });
      return { accessToken, refreshToken };
    });

    if (!rotated) {
      throw new AppError(401, 'REFRESH_REUSE_DETECTED', 'Session family was revoked');
    }
    return rotated;
  });

  app.post('/auth/logout', { preHandler: app.authenticate }, async (request) => {
    await pool.query('UPDATE sessions SET revoked_at=now() WHERE id=$1', [request.auth?.sessionId]);
    return { ok: true };
  });

  app.post('/auth/logout-all', { preHandler: app.authenticate }, async (request) => {
    await pool.query('UPDATE sessions SET revoked_at=now() WHERE user_id=$1', [request.auth?.userId]);
    return { ok: true };
  });

  app.get('/auth/sessions', { preHandler: app.authenticate }, async (request) => {
    const result = await pool.query(
      'SELECT id,device,browser,os,host(ip) AS ip,last_active_at,created_at FROM sessions WHERE user_id=$1 AND revoked_at IS NULL ORDER BY last_active_at DESC',
      [request.auth?.userId]
    );
    return { items: result.rows };
  });

  app.delete('/auth/sessions/:sessionId', { preHandler: app.authenticate }, async (request) => {
    const params = z.object({ sessionId: z.string().uuid() }).parse(request.params);
    await pool.query('UPDATE sessions SET revoked_at=now() WHERE id=$1 AND user_id=$2', [
      params.sessionId,
      request.auth?.userId
    ]);
    return { ok: true };
  });

  app.post('/auth/verify-email', async (request) => {
    const body = z.object({ token: z.string().min(20) }).parse(request.body);
    const verified = await withTransaction(async (client) => {
      const token = await client.query<{ id: string; user_id: string }>(
        'SELECT id,user_id FROM email_verification_tokens WHERE token_hash=$1 AND used_at IS NULL AND expires_at>now() FOR UPDATE',
        [sha256(body.token)]
      );
      const row = token.rows[0];
      if (!row) return false;
      await client.query('UPDATE email_verification_tokens SET used_at=now() WHERE id=$1', [row.id]);
      await client.query('UPDATE users SET email_verified_at=now() WHERE id=$1', [row.user_id]);
      return true;
    });
    if (!verified) throw new AppError(400, 'INVALID_VERIFICATION_TOKEN', 'Token is invalid or expired');
    return { ok: true };
  });

  app.post('/auth/forgot-password', {
    config: { rateLimit: { max: 5, timeWindow: '15 minutes' } }
  }, async (request) => {
    const body = z.object({ email: z.string().email().transform((v) => v.toLowerCase()) }).parse(request.body);
    const user = await pool.query<{ id: string }>('SELECT id FROM users WHERE email=$1', [body.email]);
    const row = user.rows[0];
    if (row) {
      const token = randomToken();
      await pool.query(
        'INSERT INTO password_reset_tokens (user_id,token_hash,expires_at) VALUES ($1,$2,now()+interval \'1 hour\')',
        [row.id, sha256(token)]
      );
      await notificationQueue.add('password.reset', { email: body.email, token });
    }
    return { ok: true };
  });

  app.post('/auth/reset-password', async (request) => {
    const body = z.object({
      token: z.string().min(20),
      password: z.string().min(12).max(128)
    }).parse(request.body);
    const passwordHash = await hashPassword(body.password);
    const changed = await withTransaction(async (client) => {
      const token = await client.query<{ id: string; user_id: string }>(
        'SELECT id,user_id FROM password_reset_tokens WHERE token_hash=$1 AND used_at IS NULL AND expires_at>now() FOR UPDATE',
        [sha256(body.token)]
      );
      const row = token.rows[0];
      if (!row) return false;
      await client.query('UPDATE password_reset_tokens SET used_at=now() WHERE id=$1', [row.id]);
      await client.query('UPDATE users SET password_hash=$1 WHERE id=$2', [passwordHash, row.user_id]);
      await client.query('UPDATE sessions SET revoked_at=now() WHERE user_id=$1', [row.user_id]);
      return true;
    });
    if (!changed) throw new AppError(400, 'INVALID_RESET_TOKEN', 'Token is invalid or expired');
    return { ok: true };
  });
}
