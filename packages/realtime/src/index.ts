import { z } from 'zod';

const base = {
  id: z.string().uuid(),
  room: z.string().min(1),
  occurredAt: z.string(),
  sequence: z.number().int().nonnegative().optional()
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
      attachmentIds: z.array(z.string().uuid()).optional(),
      createdAt: z.string()
    })
  }),
  z.object({
    ...base,
    type: z.literal('message.updated'),
    payload: z.object({
      id: z.string().uuid(),
      body: z.string(),
      editedAt: z.string()
    })
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
      status: z.enum([
        'online',
        'idle',
        'do-not-disturb',
        'offline'
      ]),
      customText: z.string().nullable(),
      lastSeenAt: z.string().nullable(),
      connectedDevices: z.number().int().nonnegative(),
      activeWorkspaceId: z.string().uuid().nullable()
    })
  }),
  z.object({
    ...base,
    type: z.enum(['typing.started', 'typing.stopped']),
    payload: z.object({
      userId: z.string().uuid(),
      expiresAt: z.string().nullable()
    })
  }),
  z.object({
    ...base,
    type: z.enum(['channel.created', 'channel.updated']),
    payload: z.object({
      channelId: z.string().uuid(),
      workspaceId: z.string().uuid()
    })
  }),
  z.object({
    ...base,
    type: z.enum(['member.joined', 'member.left']),
    payload: z.object({
      workspaceId: z.string().uuid(),
      userId: z.string().uuid()
    })
  }),
  z.object({
    ...base,
    type: z.enum(['call.started', 'call.ended']),
    payload: z.object({ callId: z.string().uuid() })
  })
]);

export type RealtimeEvent = z.infer<typeof realtimeEventSchema>;
export type SequencedRealtimeEvent = RealtimeEvent & {
  sequence: number;
};

export const realtimeControlMessageSchema = z.discriminatedUnion(
  'type',
  [
    z.object({
      type: z.literal('session.ready'),
      occurredAt: z.string(),
      latestSequence: z.number().int().nonnegative()
    }),
    z.object({
      type: z.literal('session.resumed'),
      occurredAt: z.string(),
      latestSequence: z.number().int().nonnegative(),
      replayedCount: z.number().int().nonnegative(),
      truncated: z.boolean()
    })
  ]
);

export type RealtimeControlMessage = z.infer<
  typeof realtimeControlMessageSchema
>;

export const clientRealtimeMessageSchema = z.discriminatedUnion(
  'type',
  [
    z.object({
      type: z.literal('room.subscribe'),
      room: z.string().min(1)
    }),
    z.object({
      type: z.literal('room.unsubscribe'),
      room: z.string().min(1)
    }),
    z.object({ type: z.literal('presence.heartbeat') }),
    z.object({
      type: z.literal('session.resume'),
      lastSequence: z.number().int().nonnegative(),
      rooms: z.array(z.string().min(1)).max(100)
    }),
    z.object({
      type: z.literal('view.active'),
      room: z.string().min(1).nullable()
    }),
    z.object({
      type: z.enum(['typing.started', 'typing.stopped']),
      room: z.string().min(1)
    })
  ]
);

export type ClientRealtimeMessage = z.infer<
  typeof clientRealtimeMessageSchema
>;
