import { z } from "zod";

const base = {
  id: z.string().uuid(),
  room: z.string().min(1),
  occurredAt: z.string(),
  sequence: z.number().int().nonnegative().optional(),
};

export const webRtcSignalSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("offer"),
    sdp: z.string().min(1).max(262_144),
  }),
  z.object({
    kind: z.literal("answer"),
    sdp: z.string().min(1).max(262_144),
  }),
  z.object({
    kind: z.literal("ice"),
    candidate: z.string().max(8_192),
    sdpMid: z.string().max(256).nullable(),
    sdpMLineIndex: z.number().int().nonnegative().nullable(),
    usernameFragment: z.string().max(256).nullable().optional(),
  }),
]);

export type WebRtcSignal = z.infer<typeof webRtcSignalSchema>;

const callParticipantSchema = z.object({
  id: z.string().uuid(),
  userId: z.string().uuid(),
  username: z.string(),
  displayName: z.string(),
  avatarUrl: z.string().nullable(),
  muted: z.boolean(),
  deafened: z.boolean(),
  cameraEnabled: z.boolean(),
  screenSharing: z.boolean(),
  connectionState: z.string(),
  joinedAt: z.string(),
});

export const realtimeEventSchema = z.discriminatedUnion("type", [
  z.object({
    ...base,
    type: z.literal("inbox.message"),
    payload: z.object({
      messageId: z.string().uuid(),
      channelId: z.string().uuid().nullable(),
      conversationId: z.string().uuid().nullable(),
      senderId: z.string().uuid(),
      createdAt: z.string(),
    }),
  }),
  z.object({
    ...base,
    type: z.literal("message.created"),
    payload: z.object({
      id: z.string().uuid(),
      channelId: z.string().uuid().nullable(),
      conversationId: z.string().uuid().nullable(),
      senderId: z.string().uuid(),
      body: z.string(),
      encryptionVersion: z.literal("libsignal-v1").nullable().optional(),
      encryptedPayload: z.string().max(262_144).nullable().optional(),
      clientMessageId: z.string().uuid().nullable(),
      attachmentIds: z.array(z.string().uuid()).optional(),
      createdAt: z.string(),
    }),
  }),
  z.object({
    ...base,
    type: z.literal("message.updated"),
    payload: z.object({
      id: z.string().uuid(),
      body: z.string(),
      editedAt: z.string(),
    }),
  }),
  z.object({
    ...base,
    type: z.literal("message.deleted"),
    payload: z.object({ id: z.string().uuid() }),
  }),
  z.object({
    ...base,
    type: z.enum(["reaction.created", "reaction.deleted"]),
    payload: z.object({
      messageId: z.string().uuid(),
      userId: z.string().uuid(),
      emoji: z.string(),
    }),
  }),
  z.object({
    ...base,
    type: z.literal("presence.updated"),
    payload: z.object({
      userId: z.string().uuid(),
      status: z.enum(["online", "idle", "do-not-disturb", "offline"]),
      customText: z.string().nullable(),
      lastSeenAt: z.string().nullable(),
      connectedDevices: z.number().int().nonnegative(),
      activeWorkspaceId: z.string().uuid().nullable(),
    }),
  }),
  z.object({
    ...base,
    type: z.enum(["typing.started", "typing.stopped"]),
    payload: z.object({
      userId: z.string().uuid(),
      expiresAt: z.string().nullable(),
    }),
  }),
  z.object({
    ...base,
    type: z.enum(["channel.created", "channel.updated"]),
    payload: z.object({
      channelId: z.string().uuid(),
      workspaceId: z.string().uuid(),
    }),
  }),
  z.object({
    ...base,
    type: z.enum(["member.joined", "member.left"]),
    payload: z.object({
      workspaceId: z.string().uuid(),
      userId: z.string().uuid(),
    }),
  }),
  z.object({
    ...base,
    type: z.literal("call.started"),
    payload: z.object({
      callId: z.string().uuid(),
      kind: z.enum(["voice", "video"]),
      channelId: z.string().uuid().nullable(),
      conversationId: z.string().uuid().nullable(),
      startedAt: z.string(),
    }),
  }),
  z.object({
    ...base,
    type: z.literal("call.ended"),
    payload: z.object({
      callId: z.string().uuid(),
      endedAt: z.string(),
    }),
  }),
  z.object({
    ...base,
    type: z.enum([
      "call.participant.joined",
      "call.participant.left",
      "call.participant.updated",
    ]),
    payload: z.object({
      callId: z.string().uuid(),
      participant: callParticipantSchema,
    }),
  }),
  z.object({
    ...base,
    type: z.literal("call.signal"),
    payload: z.object({
      callId: z.string().uuid(),
      fromParticipantId: z.string().uuid(),
      fromUserId: z.string().uuid(),
      signal: webRtcSignalSchema,
    }),
  }),
  z.object({
    ...base,
    type: z.literal("call.speaking"),
    payload: z.object({
      callId: z.string().uuid(),
      participantId: z.string().uuid(),
      userId: z.string().uuid(),
      speaking: z.boolean(),
      expiresAt: z.string().nullable(),
    }),
  }),
]);

export type RealtimeEvent = z.infer<typeof realtimeEventSchema>;
export type SequencedRealtimeEvent = RealtimeEvent & {
  sequence: number;
};

export const realtimeControlMessageSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("session.ready"),
    occurredAt: z.string(),
    latestSequence: z.number().int().nonnegative(),
  }),
  z.object({
    type: z.literal("session.resumed"),
    occurredAt: z.string(),
    latestSequence: z.number().int().nonnegative(),
    replayedCount: z.number().int().nonnegative(),
    truncated: z.boolean(),
  }),
]);

export type RealtimeControlMessage = z.infer<
  typeof realtimeControlMessageSchema
>;

export const clientRealtimeMessageSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("room.subscribe"),
    room: z.string().min(1),
  }),
  z.object({
    type: z.literal("room.unsubscribe"),
    room: z.string().min(1),
  }),
  z.object({ type: z.literal("presence.heartbeat") }),
  z.object({
    type: z.literal("session.resume"),
    lastSequence: z.number().int().nonnegative(),
    rooms: z.array(z.string().min(1)).max(100),
  }),
  z.object({
    type: z.literal("view.active"),
    room: z.string().min(1).nullable(),
  }),
  z.object({
    type: z.enum(["typing.started", "typing.stopped"]),
    room: z.string().min(1),
  }),
  z.object({
    type: z.literal("call.signal"),
    callId: z.string().uuid(),
    targetParticipantId: z.string().uuid(),
    signal: webRtcSignalSchema,
  }),
  z.object({
    type: z.literal("call.speaking"),
    callId: z.string().uuid(),
    speaking: z.boolean(),
  }),
]);

export type ClientRealtimeMessage = z.infer<typeof clientRealtimeMessageSchema>;
