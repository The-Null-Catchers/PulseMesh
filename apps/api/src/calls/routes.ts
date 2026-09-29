import type { FastifyInstance } from 'fastify';
import { createHmac, randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { RealtimeEvent } from '@pulsemesh/realtime';
import {
  assertWorkspacePermission,
  canAccessChannel,
  canAccessConversation
} from '../authorization/service.js';
import { config } from '../config.js';
import { pool, withTransaction } from '../db/index.js';
import { AppError } from '../errors.js';
import { publishRealtime } from '../realtime/bus.js';
import {
  callDestinationRoom,
  canAccessCall,
  getCallContext
} from './service.js';

type CallRow = {
  id: string;
  channel_id: string | null;
  conversation_id: string | null;
  created_by: string;
  kind: 'voice' | 'video';
  status: string;
  provider: string;
  started_at: Date;
  ended_at: Date | null;
};

type ParticipantRow = {
  id: string;
  user_id: string;
  username: string;
  display_name: string;
  avatar_url: string | null;
  muted: boolean;
  deafened: boolean;
  camera_enabled: boolean;
  screen_sharing: boolean;
  connection_state: string;
  joined_at: Date;
};

function participantPayload(row: ParticipantRow) {
  return {
    id: row.id,
    userId: row.user_id,
    username: row.username,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    muted: row.muted,
    deafened: row.deafened,
    cameraEnabled: row.camera_enabled,
    screenSharing: row.screen_sharing,
    connectionState: row.connection_state,
    joinedAt: row.joined_at.toISOString()
  };
}

async function participants(callId: string) {
  const result = await pool.query<ParticipantRow>(
    'SELECT p.id,p.user_id,u.username,u.display_name,u.avatar_url,p.muted,p.deafened,p.camera_enabled,p.screen_sharing,p.connection_state,p.joined_at FROM call_participants p JOIN users u ON u.id=p.user_id WHERE p.call_id=$1 AND p.left_at IS NULL ORDER BY p.joined_at,p.id',
    [callId]
  );
  return result.rows.map(participantPayload);
}

async function callResponse(call: CallRow) {
  return {
    id: call.id,
    channelId: call.channel_id,
    conversationId: call.conversation_id,
    createdBy: call.created_by,
    kind: call.kind,
    status: call.status,
    provider: call.provider,
    startedAt: call.started_at.toISOString(),
    endedAt: call.ended_at?.toISOString() ?? null,
    participants: await participants(call.id)
  };
}

async function destinationAccess(input: {
  userId: string;
  channelId?: string;
  conversationId?: string;
}): Promise<{ room: string; workspaceId: string | null }> {
  if (input.channelId) {
    const channel = await pool.query<{
      workspace_id: string;
      kind: string;
      archived_at: Date | null;
    }>(
      'SELECT workspace_id,kind,archived_at FROM channels WHERE id=$1',
      [input.channelId]
    );
    const row = channel.rows[0];
    if (
      !row ||
      row.kind !== 'voice' ||
      row.archived_at ||
      !(await canAccessChannel(input.userId, input.channelId))
    ) {
      throw new AppError(
        403,
        'VOICE_CHANNEL_ACCESS_DENIED',
        'Voice channel access denied'
      );
    }
    await assertWorkspacePermission(
      input.userId,
      row.workspace_id,
      'call.create'
    );
    return {
      room: 'channel:' + input.channelId,
      workspaceId: row.workspace_id
    };
  }

  if (
    input.conversationId &&
    (await canAccessConversation(
      input.userId,
      input.conversationId
    ))
  ) {
    return {
      room: 'conversation:' + input.conversationId,
      workspaceId: null
    };
  }

  throw new AppError(
    403,
    'CALL_ACCESS_DENIED',
    'Call destination access denied'
  );
}

async function publishParticipant(
  type:
    | 'call.participant.joined'
    | 'call.participant.left'
    | 'call.participant.updated',
  room: string,
  callId: string,
  participant: ReturnType<typeof participantPayload>
): Promise<void> {
  const event: RealtimeEvent = {
    id: randomUUID(),
    type,
    room,
    occurredAt: new Date().toISOString(),
    payload: { callId, participant }
  };
  await publishRealtime(event);
}

export async function callRoutes(
  app: FastifyInstance
): Promise<void> {
  app.get(
    '/calls/ice-config',
    { preHandler: app.authenticate },
    async (request) => {
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const expiresAt = Math.floor(Date.now() / 1000) + 3600;
      const username = expiresAt + ':' + userId;
      const credential = createHmac(
        'sha1',
        config.TURN_SHARED_SECRET
      )
        .update(username)
        .digest('base64');

      return {
        iceServers: [
          {
            urls: config.TURN_URLS.split(',')
              .map((value) => value.trim())
              .filter(Boolean),
            username,
            credential
          }
        ],
        expiresAt: new Date(expiresAt * 1000).toISOString()
      };
    }
  );

  app.post(
    '/calls',
    {
      preHandler: app.authenticate,
      config: {
        rateLimit: { max: 20, timeWindow: '1 minute' }
      }
    },
    async (request, reply) => {
      const body = z
        .object({
          channelId: z.string().uuid().optional(),
          conversationId: z.string().uuid().optional(),
          kind: z.literal('voice').default('voice')
        })
        .refine(
          (value) =>
            Boolean(value.channelId) !==
            Boolean(value.conversationId),
          {
            message:
              'Exactly one call destination is required'
          }
        )
        .parse(request.body);

      const userId = request.auth?.userId;
      const sessionId = request.auth?.sessionId;
      if (!userId || !sessionId) throw new Error('Missing user');

      const access = await destinationAccess({
        userId,
        ...(body.channelId
          ? { channelId: body.channelId }
          : {}),
        ...(body.conversationId
          ? { conversationId: body.conversationId }
          : {})
      });

      const destinationKey = body.channelId
        ? 'channel:' + body.channelId
        : 'conversation:' + body.conversationId;

      const outcome = await withTransaction(async (client) => {
        await client.query(
          'SELECT pg_advisory_xact_lock(hashtext($1))',
          ['pulsemesh-call:' + destinationKey]
        );

        const existing = await client.query<CallRow>(
          body.channelId
            ? "SELECT id,channel_id,conversation_id,created_by,kind,status,provider,started_at,ended_at FROM calls WHERE channel_id=$1 AND status='active' LIMIT 1"
            : "SELECT id,channel_id,conversation_id,created_by,kind,status,provider,started_at,ended_at FROM calls WHERE conversation_id=$1 AND status='active' LIMIT 1",
          [body.channelId ?? body.conversationId]
        );

        let call = existing.rows[0];
        let created = false;

        if (!call) {
          const inserted = await client.query<CallRow>(
            "INSERT INTO calls (channel_id,conversation_id,created_by,kind,status,provider) VALUES ($1,$2,$3,$4,'active','mesh') RETURNING id,channel_id,conversation_id,created_by,kind,status,provider,started_at,ended_at",
            [
              body.channelId ?? null,
              body.conversationId ?? null,
              userId,
              body.kind
            ]
          );
          call = inserted.rows[0];
          created = true;
        }

        if (!call) throw new Error('Call creation failed');

        const participant = await client.query<ParticipantRow>(
          "INSERT INTO call_participants (call_id,user_id,session_id,connection_state) VALUES ($1,$2,$3,'connected') ON CONFLICT (call_id,session_id) WHERE session_id IS NOT NULL AND left_at IS NULL DO UPDATE SET connection_state='connected',updated_at=now() RETURNING id,user_id,(SELECT username FROM users WHERE id=user_id) AS username,(SELECT display_name FROM users WHERE id=user_id) AS display_name,(SELECT avatar_url FROM users WHERE id=user_id) AS avatar_url,muted,deafened,camera_enabled,screen_sharing,connection_state,joined_at",
          [call.id, userId, sessionId]
        );

        const participantRow = participant.rows[0];
        if (!participantRow) {
          throw new Error('Call participant creation failed');
        }

        return { call, participantRow, created };
      });

      if (outcome.created) {
        const event: RealtimeEvent = {
          id: randomUUID(),
          type: 'call.started',
          room: access.room,
          occurredAt: new Date().toISOString(),
          payload: {
            callId: outcome.call.id,
            kind: outcome.call.kind,
            channelId: outcome.call.channel_id,
            conversationId: outcome.call.conversation_id,
            startedAt: outcome.call.started_at.toISOString()
          }
        };
        await publishRealtime(event);
      }

      await publishParticipant(
        'call.participant.joined',
        access.room,
        outcome.call.id,
        participantPayload(outcome.participantRow)
      );

      return reply
        .code(outcome.created ? 201 : 200)
        .send(await callResponse(outcome.call));
    }
  );

  app.get(
    '/calls/:callId',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ callId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const context = await getCallContext(params.callId);
      if (!(await canAccessCall(userId, context))) {
        throw new AppError(
          403,
          'CALL_ACCESS_DENIED',
          'Call access denied'
        );
      }

      return callResponse(context);
    }
  );

  app.post(
    '/calls/:callId/join',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ callId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      const sessionId = request.auth?.sessionId;
      if (!userId || !sessionId) throw new Error('Missing user');

      const context = await getCallContext(params.callId);
      if (
        context.status !== 'active' ||
        !(await canAccessCall(userId, context))
      ) {
        throw new AppError(
          403,
          'CALL_JOIN_DENIED',
          'Call is not available'
        );
      }

      const result = await pool.query<ParticipantRow>(
        "INSERT INTO call_participants (call_id,user_id,session_id,connection_state) VALUES ($1,$2,$3,'connected') ON CONFLICT (call_id,session_id) WHERE session_id IS NOT NULL AND left_at IS NULL DO UPDATE SET connection_state='connected',updated_at=now() RETURNING id,user_id,(SELECT username FROM users WHERE id=user_id) AS username,(SELECT display_name FROM users WHERE id=user_id) AS display_name,(SELECT avatar_url FROM users WHERE id=user_id) AS avatar_url,muted,deafened,camera_enabled,screen_sharing,connection_state,joined_at",
        [context.id, userId, sessionId]
      );
      const participant = result.rows[0];
      if (!participant) throw new Error('Call join failed');

      await publishParticipant(
        'call.participant.joined',
        callDestinationRoom(context),
        context.id,
        participantPayload(participant)
      );

      return {
        call: await callResponse(context),
        participant: participantPayload(participant)
      };
    }
  );

  app.patch(
    '/calls/:callId/participant',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ callId: z.string().uuid() })
        .parse(request.params);
      const body = z
        .object({
          muted: z.boolean().optional(),
          deafened: z.boolean().optional(),
          connectionState: z
            .enum([
              'connecting',
              'connected',
              'reconnecting',
              'failed'
            ])
            .optional()
        })
        .refine(
          (value) => Object.keys(value).length > 0,
          { message: 'At least one state field is required' }
        )
        .parse(request.body);

      const userId = request.auth?.userId;
      const sessionId = request.auth?.sessionId;
      if (!userId || !sessionId) throw new Error('Missing user');

      const context = await getCallContext(params.callId);
      if (!(await canAccessCall(userId, context))) {
        throw new AppError(
          403,
          'CALL_ACCESS_DENIED',
          'Call access denied'
        );
      }

      const result = await pool.query<ParticipantRow>(
        'UPDATE call_participants p SET muted=COALESCE($4,muted),deafened=COALESCE($5,deafened),connection_state=COALESCE($6,connection_state),updated_at=now() FROM users u WHERE p.call_id=$1 AND p.user_id=$2 AND p.session_id=$3 AND p.left_at IS NULL AND u.id=p.user_id RETURNING p.id,p.user_id,u.username,u.display_name,u.avatar_url,p.muted,p.deafened,p.camera_enabled,p.screen_sharing,p.connection_state,p.joined_at',
        [
          params.callId,
          userId,
          sessionId,
          body.muted ?? null,
          body.deafened ?? null,
          body.connectionState ?? null
        ]
      );
      const participant = result.rows[0];

      if (!participant) {
        throw new AppError(
          404,
          'CALL_PARTICIPANT_NOT_FOUND',
          'Active call participant was not found'
        );
      }

      const payload = participantPayload(participant);
      await publishParticipant(
        'call.participant.updated',
        callDestinationRoom(context),
        context.id,
        payload
      );
      return payload;
    }
  );

  app.post(
    '/calls/:callId/leave',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ callId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      const sessionId = request.auth?.sessionId;
      if (!userId || !sessionId) throw new Error('Missing user');

      const context = await getCallContext(params.callId);
      const room = callDestinationRoom(context);

      const left = await pool.query<ParticipantRow>(
        'UPDATE call_participants p SET left_at=now(),connection_state=\'disconnected\',updated_at=now() FROM users u WHERE p.call_id=$1 AND p.user_id=$2 AND p.session_id=$3 AND p.left_at IS NULL AND u.id=p.user_id RETURNING p.id,p.user_id,u.username,u.display_name,u.avatar_url,p.muted,p.deafened,p.camera_enabled,p.screen_sharing,p.connection_state,p.joined_at',
        [params.callId, userId, sessionId]
      );

      const participant = left.rows[0];
      if (participant) {
        await publishParticipant(
          'call.participant.left',
          room,
          context.id,
          participantPayload(participant)
        );
      }

      const remaining = await pool.query(
        'SELECT 1 FROM call_participants WHERE call_id=$1 AND left_at IS NULL LIMIT 1',
        [params.callId]
      );

      if (!remaining.rowCount && context.status === 'active') {
        const ended = await pool.query<{ ended_at: Date }>(
          "UPDATE calls SET status='ended',ended_at=now(),updated_at=now() WHERE id=$1 AND status='active' RETURNING ended_at",
          [params.callId]
        );
        const endedAt = ended.rows[0]?.ended_at;
        if (endedAt) {
          const event: RealtimeEvent = {
            id: randomUUID(),
            type: 'call.ended',
            room,
            occurredAt: new Date().toISOString(),
            payload: {
              callId: context.id,
              endedAt: endedAt.toISOString()
            }
          };
          await publishRealtime(event);
        }
      }

      return { ok: true };
    }
  );

  app.post(
    '/calls/:callId/end',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ callId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const context = await getCallContext(params.callId);
      if (context.channel_id && context.workspace_id) {
        await assertWorkspacePermission(
          userId,
          context.workspace_id,
          'call.manage'
        );
      } else if (context.conversation_id) {
        const role = await pool.query<{ role: string }>(
          'SELECT role FROM conversation_members WHERE conversation_id=$1 AND user_id=$2',
          [context.conversation_id, userId]
        );
        if (
          context.created_by !== userId &&
          !['owner', 'admin'].includes(
            role.rows[0]?.role ?? ''
          )
        ) {
          throw new AppError(
            403,
            'CALL_MANAGE_DENIED',
            'Call management permission required'
          );
        }
      }

      const result = await withTransaction(async (client) => {
        await client.query(
          "UPDATE call_participants SET left_at=COALESCE(left_at,now()),connection_state='disconnected',updated_at=now() WHERE call_id=$1 AND left_at IS NULL",
          [params.callId]
        );
        return client.query<{ ended_at: Date }>(
          "UPDATE calls SET status='ended',ended_at=COALESCE(ended_at,now()),updated_at=now() WHERE id=$1 AND status='active' RETURNING ended_at",
          [params.callId]
        );
      });

      const endedAt = result.rows[0]?.ended_at;
      if (endedAt) {
        const event: RealtimeEvent = {
          id: randomUUID(),
          type: 'call.ended',
          room: callDestinationRoom(context),
          occurredAt: new Date().toISOString(),
          payload: {
            callId: context.id,
            endedAt: endedAt.toISOString()
          }
        };
        await publishRealtime(event);
      }

      return { ok: true };
    }
  );

  async function activeDestinationCall(
    userId: string,
    field: 'channel_id' | 'conversation_id',
    destinationId: string
  ) {
    const allowed =
      field === 'channel_id'
        ? await canAccessChannel(userId, destinationId)
        : await canAccessConversation(userId, destinationId);

    if (!allowed) {
      throw new AppError(
        403,
        'CALL_ACCESS_DENIED',
        'Call destination access denied'
      );
    }

    const result = await pool.query<CallRow>(
      'SELECT id,channel_id,conversation_id,created_by,kind,status,provider,started_at,ended_at FROM calls WHERE ' +
        field +
        "=$1 AND status='active' LIMIT 1",
      [destinationId]
    );
    const call = result.rows[0];
    return call ? callResponse(call) : null;
  }

  app.get(
    '/channels/:channelId/call',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');
      return {
        call: await activeDestinationCall(
          userId,
          'channel_id',
          params.channelId
        )
      };
    }
  );

  app.get(
    '/conversations/:conversationId/call',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');
      return {
        call: await activeDestinationCall(
          userId,
          'conversation_id',
          params.conversationId
        )
      };
    }
  );
}
