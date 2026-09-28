import { z } from 'zod';

const base = {
  id: z.string().uuid(),
  room: z.string().min(1),
  occurredAt: z.string()
};

export const realtimeEventSchema = z.discriminatedUnion('type', [
  z.object({
    ...base,
    type: z.literal('message.created'),
    payload: z.object({
      id: z.string().uuid(),
      channelId: z.string().uuid().nullable(),
      conversationId: z.string().uuid().nullable(),
      senderId: z.string().uuid(),
      body: z.string(),
      clientMessageId: z.string().uuid().nullable(),
      createdAt: z.string()
    })
  }),
  z.object({
    ...base,
    type: z.literal('message.updated'),
    payload: z.object({ id: z.string().uuid(), body: z.string(), editedAt: z.string() })
  }),
  z.object({
    ...base,
    type: z.literal('message.deleted'),
    payload: z.object({ id: z.string().uuid() })
  }),
  z.object({
    ...base,
    type: z.enum(['reaction.created', 'reaction.deleted']),
    payload: z.object({
      messageId: z.string().uuid(),
      userId: z.string().uuid(),
      emoji: z.string()
    })
  }),
  z.object({
    ...base,
    type: z.literal('presence.updated'),
    payload: z.object({
      userId: z.string().uuid(),
      status: z.enum(['online', 'idle', 'do-not-disturb', 'offline']),
      customText: z.string().nullable(),
      lastSeenAt: z.string().nullable()
    })
  }),
  z.object({
    ...base,
    type: z.enum(['typing.started', 'typing.stopped']),
    payload: z.object({ userId: z.string().uuid() })
  }),
  z.object({
    ...base,
    type: z.enum(['channel.created', 'channel.updated']),
    payload: z.object({ channelId: z.string().uuid(), workspaceId: z.string().uuid() })
  }),
  z.object({
    ...base,
    type: z.enum(['member.joined', 'member.left']),
    payload: z.object({ workspaceId: z.string().uuid(), userId: z.string().uuid() })
  }),
  z.object({
    ...base,
    type: z.enum(['call.started', 'call.ended']),
    payload: z.object({ callId: z.string().uuid() })
  })
]);

export type RealtimeEvent = z.infer<typeof realtimeEventSchema>;

export const clientRealtimeMessageSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('room.subscribe'), room: z.string().min(1) }),
  z.object({ type: z.literal('room.unsubscribe'), room: z.string().min(1) }),
  z.object({ type: z.literal('presence.heartbeat') }),
  z.object({ type: z.enum(['typing.started', 'typing.stopped']), room: z.string().min(1) })
]);
