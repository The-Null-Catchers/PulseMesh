import { describe, expect, it } from 'vitest';
import {
  clientRealtimeMessageSchema,
  realtimeEventSchema,
  webRtcSignalSchema
} from './index.js';

describe('realtime contracts', () => {
  it('accepts session resume with a recovery cursor', () => {
    const result = clientRealtimeMessageSchema.safeParse({
      type: 'session.resume',
      lastSequence: 42,
      rooms: [
        'workspace:5d9ad22f-b7dc-4b4c-9a31-cfe8f17fc5a4',
        'channel:54285544-0c19-4c53-838d-27a1155c461b'
      ]
    });

    expect(result.success).toBe(true);
  });

  it('accepts an authorized-view hint contract', () => {
    expect(
      clientRealtimeMessageSchema.safeParse({
        type: 'view.active',
        room: 'conversation:5d9ad22f-b7dc-4b4c-9a31-cfe8f17fc5a4'
      }).success
    ).toBe(true);
  });

  it('validates targeted WebRTC signaling', () => {
    const signal = webRtcSignalSchema.safeParse({
      kind: 'ice',
      candidate: 'candidate:1 1 udp 1 203.0.113.1 50000 typ relay',
      sdpMid: '0',
      sdpMLineIndex: 0
    });
    expect(signal.success).toBe(true);

    expect(
      clientRealtimeMessageSchema.safeParse({
        type: 'call.signal',
        callId: '5d9ad22f-b7dc-4b4c-9a31-cfe8f17fc5a4',
        targetParticipantId:
          '54285544-0c19-4c53-838d-27a1155c461b',
        signal: {
          kind: 'offer',
          sdp: 'v=0\r\n'
        }
      }).success
    ).toBe(true);
  });

  it('requires typing events to carry an expiry contract', () => {
    const result = realtimeEventSchema.safeParse({
      id: '67d4e381-a0df-4d82-9177-cb1daa78bd74',
      type: 'typing.started',
      room: 'channel:54285544-0c19-4c53-838d-27a1155c461b',
      occurredAt: new Date().toISOString(),
      sequence: 9,
      payload: {
        userId: '78119f40-5b7e-48fa-a6da-d4d19d2cba45',
        expiresAt: new Date(Date.now() + 8_000).toISOString()
      }
    });

    expect(result.success).toBe(true);
  });

  it('supports attachment IDs on created messages', () => {
    const result = realtimeEventSchema.safeParse({
      id: '67d4e381-a0df-4d82-9177-cb1daa78bd74',
      type: 'message.created',
      room: 'channel:54285544-0c19-4c53-838d-27a1155c461b',
      occurredAt: new Date().toISOString(),
      payload: {
        id: 'f113742e-2534-443e-8353-34382100dfdf',
        channelId: '54285544-0c19-4c53-838d-27a1155c461b',
        conversationId: null,
        senderId: '78119f40-5b7e-48fa-a6da-d4d19d2cba45',
        body: '',
        clientMessageId: null,
        attachmentIds: [
          'd6efc282-7d92-4dcf-812d-18328892ec49'
        ],
        createdAt: new Date().toISOString()
      }
    });

    expect(result.success).toBe(true);
  });

  it('rejects negative recovery cursors', () => {
    const result = clientRealtimeMessageSchema.safeParse({
      type: 'session.resume',
      lastSequence: -1,
      rooms: []
    });

    expect(result.success).toBe(false);
  });
});
