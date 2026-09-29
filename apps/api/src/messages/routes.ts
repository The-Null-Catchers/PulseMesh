import type { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { RealtimeEvent } from '@pulsemesh/realtime';
import { decodeCursor, encodeCursor } from '@pulsemesh/shared';
import { pool, withTransaction } from '../db/index.js';
import {
  canAccessChannel,
  canSendToChannel
} from '../authorization/service.js';
import { AppError } from '../errors.js';
import { publishRealtime } from '../realtime/bus.js';
import { attachReadyFiles } from './attachments.js';
import { createMentionNotifications } from './mentions.js';
import { enforceWorkspaceMessagePolicy } from '../moderation/anti-spam.js';
import { channelWorkspaceId } from '../moderation/service.js';
import { messagesCreated } from '../observability/metrics.js';

const sendSchema = z
  .object({
    clientMessageId: z.string().uuid().optional(),
    body: z.string().trim().max(20_000).default(''),
    replyToMessageId: z.string().uuid().optional(),
    attachmentIds: z
      .array(z.string().uuid())
      .max(10)
      .default([])
  })
  .refine(
    (value) => value.body.length > 0 || value.attachmentIds.length > 0,
    { message: 'A message must contain text or an attachment' }
  );

type MessageRow = {
  id: string;
  body: string;
  created_at: Date;
  edited_at: Date | null;
  client_message_id: string | null;
  reply_to_message_id: string | null;
  sender_id: string;
  username: string;
  display_name: string;
  avatar_url: string | null;
  attachments: unknown[];
};

export async function messageRoutes(
  app: FastifyInstance
): Promise<void> {
  app.get(
    '/channels/:channelId/messages',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const query = z
        .object({
          cursor: z.string().optional(),
          limit: z.coerce.number().int().min(1).max(100).default(50)
        })
        .parse(request.query);
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

      const values: unknown[] = [params.channelId, userId];
      let cursorClause = '';
      if (query.cursor) {
        const cursor = decodeCursor<{
          createdAt: string;
          id: string;
        }>(query.cursor);
        values.push(cursor.createdAt, cursor.id);
        cursorClause =
          'AND (m.created_at,m.id) < ($3::timestamptz,$4::uuid)';
      }
      values.push(query.limit + 1);

      const result = await pool.query<MessageRow>(
        "SELECT m.id,m.body,m.created_at,m.edited_at,m.client_message_id,m.reply_to_message_id,u.id AS sender_id,u.username,u.display_name,u.avatar_url,COALESCE((SELECT json_agg(json_build_object('id',f.id,'name',f.original_name,'mimeType',COALESCE(f.detected_mime_type,f.mime_type),'sizeBytes',f.size_bytes,'width',f.width,'height',f.height,'durationMs',f.duration_ms,'hasThumbnail',(f.thumbnail_key IS NOT NULL)) ORDER BY ma.position) FROM message_attachments ma JOIN files f ON f.id=ma.file_id WHERE ma.message_id=m.id AND f.status='ready'),'[]'::json) AS attachments FROM messages m JOIN users u ON u.id=m.sender_user_id WHERE m.channel_id=$1 AND m.deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM message_hidden_users h WHERE h.message_id=m.id AND h.user_id=$2) " +
          cursorClause +
          ' ORDER BY m.created_at DESC,m.id DESC LIMIT $' +
          values.length,
        values
      );

      const hasMore = result.rows.length > query.limit;
      const rows = result.rows.slice(0, query.limit);
      const last = rows[rows.length - 1];

      return {
        items: rows.map((row) => ({
          id: row.id,
          clientMessageId: row.client_message_id,
          channelId: params.channelId,
          conversationId: null,
          body: row.body,
          replyToMessageId: row.reply_to_message_id,
          attachments: row.attachments,
          createdAt: row.created_at.toISOString(),
          editedAt: row.edited_at?.toISOString() ?? null,
          sender: {
            id: row.sender_id,
            username: row.username,
            displayName: row.display_name,
            avatarUrl: row.avatar_url
          }
        })),
        nextCursor:
          hasMore && last
            ? encodeCursor({
                createdAt: last.created_at.toISOString(),
                id: last.id
              })
            : null
      };
    }
  );

  app.post(
    '/channels/:channelId/messages',
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } }
    },
    async (request, reply) => {
      const params = z
        .object({ channelId: z.string().uuid() })
        .parse(request.params);
      const body = sendSchema.parse(request.body);
      const userId = request.auth?.userId;

      if (
        !userId ||
        !(await canSendToChannel(userId, params.channelId))
      ) {
        throw new AppError(
          403,
          'MESSAGE_SEND_DENIED',
          'You cannot send to this channel'
        );
      }

      const workspaceId = await channelWorkspaceId(params.channelId);
      await enforceWorkspaceMessagePolicy({
        workspaceId,
        userId,
        body: body.body
      });

      const created = await withTransaction(async (client) => {
        const result = await client.query<{
          id: string;
          created_at: Date;
          client_message_id: string | null;
        }>(
          'INSERT INTO messages (channel_id,sender_user_id,client_message_id,body,reply_to_message_id) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (sender_user_id,client_message_id) WHERE client_message_id IS NOT NULL DO UPDATE SET client_message_id=EXCLUDED.client_message_id RETURNING id,created_at,client_message_id',
          [
            params.channelId,
            userId,
            body.clientMessageId ?? null,
            body.body,
            body.replyToMessageId ?? null
          ]
        );

        const message = result.rows[0];
        if (!message) throw new Error('Message creation failed');

        const attachmentIds = await attachReadyFiles(
          client,
          message.id,
          userId,
          body.attachmentIds
        );
        return { message, attachmentIds };
      });

      await createMentionNotifications({
        messageId: created.message.id,
        senderUserId: userId,
        body: body.body,
        channelId: params.channelId
      });

      const event: RealtimeEvent = {
        id: randomUUID(),
        type: 'message.created',
        room: 'channel:' + params.channelId,
        occurredAt: new Date().toISOString(),
        payload: {
          id: created.message.id,
          channelId: params.channelId,
          conversationId: null,
          senderId: userId,
          body: body.body,
          clientMessageId: created.message.client_message_id,
          attachmentIds: created.attachmentIds,
          createdAt: created.message.created_at.toISOString()
        }
      };

      await publishRealtime(event);
      messagesCreated.inc({ destination: 'channel' });
      return reply.code(201).send(event.payload);
    }
  );
}
