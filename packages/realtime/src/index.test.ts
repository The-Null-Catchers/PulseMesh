import { describe, expect, it } from 'vitest';
import {
  clientRealtimeMessageSchema,
  realtimeEventSchema
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

  it('rejects negative recovery cursors', () => {
    const result = clientRealtimeMessageSchema.safeParse({
      type: 'session.resume',
      lastSequence: -1,
      rooms: []
    });

    expect(result.success).toBe(false);
  });
});
