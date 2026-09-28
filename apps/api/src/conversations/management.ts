import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { pool } from '../db/index.js';
import { AppError } from '../errors.js';
import { canAccessConversation } from '../authorization/service.js';

async function roleFor(
  userId: string,
  conversationId: string
): Promise<string> {
  const result = await pool.query<{ role: string }>(
    'SELECT role FROM conversation_members WHERE conversation_id=$1 AND user_id=$2',
    [conversationId, userId]
  );
  return result.rows[0]?.role ?? '';
}

async function assertAdmin(
  userId: string,
  conversationId: string
): Promise<string> {
  const role = await roleFor(userId, conversationId);
  if (!['owner', 'admin'].includes(role)) {
    throw new AppError(
      403,
      'CONVERSATION_ADMIN_REQUIRED',
      'Conversation admin permission required'
    );
  }
  return role;
}

export async function conversationManagementRoutes(
  app: FastifyInstance
): Promise<void> {
  app.patch(
    '/conversations/:conversationId',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          name: z.string().min(1).max(100).optional(),
          avatarUrl: z.string().url().nullable().optional()
        })
        .parse(request.body);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      await assertAdmin(userId, params.conversationId);

      const result = await pool.query(
        "UPDATE conversations SET name=COALESCE($1,name),avatar_url=CASE WHEN $2::boolean THEN $3 ELSE avatar_url END,updated_at=now() WHERE id=$4 AND kind='group' RETURNING id,kind,name,avatar_url,updated_at",
        [
          body.name ?? null,
          Object.prototype.hasOwnProperty.call(body, 'avatarUrl'),
          body.avatarUrl ?? null,
          params.conversationId
        ]
      );

      if (!result.rowCount) {
        throw new AppError(
          400,
          'GROUP_REQUIRED',
          'Only group conversations can be customized'
        );
      }

      return result.rows[0];
    }
  );

  app.post(
    '/conversations/:conversationId/members',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({ userId: z.string().uuid() })
        .parse(request.body);
      const actorId = request.auth?.userId;
      if (!actorId) throw new Error('Missing user');

      await assertAdmin(actorId, params.conversationId);

      const group = await pool.query(
        "SELECT 1 FROM conversations WHERE id=$1 AND kind='group'",
        [params.conversationId]
      );

      if (!group.rowCount) {
        throw new AppError(
          400,
          'GROUP_REQUIRED',
          'Members can only be added to groups'
        );
      }

      await pool.query(
        "INSERT INTO conversation_members (conversation_id,user_id,role) VALUES ($1,$2,'member') ON CONFLICT (conversation_id,user_id) DO NOTHING",
        [params.conversationId, body.userId]
      );

      await pool.query(
        'UPDATE conversations SET updated_at=now() WHERE id=$1',
        [params.conversationId]
      );

      return { ok: true };
    }
  );

  app.delete(
    '/conversations/:conversationId/members/:memberId',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          conversationId: z.string().uuid(),
          memberId: z.string().uuid()
        })
        .parse(request.params);
      const actorId = request.auth?.userId;
      if (!actorId) throw new Error('Missing user');

      if (actorId !== params.memberId) {
        await assertAdmin(actorId, params.conversationId);
      } else if (
        !(await canAccessConversation(actorId, params.conversationId))
      ) {
        throw new AppError(
          403,
          'CONVERSATION_ACCESS_DENIED',
          'Conversation access denied'
        );
      }

      const targetRole = await roleFor(
        params.memberId,
        params.conversationId
      );

      if (targetRole === 'owner') {
        throw new AppError(
          409,
          'OWNER_TRANSFER_REQUIRED',
          'Transfer group ownership before removing the owner'
        );
      }

      await pool.query(
        'DELETE FROM conversation_members WHERE conversation_id=$1 AND user_id=$2',
        [params.conversationId, params.memberId]
      );

      await pool.query(
        'UPDATE conversations SET updated_at=now() WHERE id=$1',
        [params.conversationId]
      );

      return { ok: true };
    }
  );

  app.put(
    '/conversations/:conversationId/members/:memberId/role',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({
          conversationId: z.string().uuid(),
          memberId: z.string().uuid()
        })
        .parse(request.params);
      const body = z
        .object({ role: z.enum(['admin', 'member']) })
        .parse(request.body);
      const actorId = request.auth?.userId;
      if (!actorId) throw new Error('Missing user');

      const actorRole = await roleFor(
        actorId,
        params.conversationId
      );

      if (actorRole !== 'owner') {
        throw new AppError(
          403,
          'CONVERSATION_OWNER_REQUIRED',
          'Only the owner can change group roles'
        );
      }

      const result = await pool.query(
        "UPDATE conversation_members SET role=$1 WHERE conversation_id=$2 AND user_id=$3 AND role<>'owner' RETURNING user_id,role",
        [body.role, params.conversationId, params.memberId]
      );

      if (!result.rowCount) {
        throw new AppError(
          404,
          'MEMBER_NOT_FOUND',
          'Member not found or role cannot be changed'
        );
      }

      return result.rows[0];
    }
  );
}
