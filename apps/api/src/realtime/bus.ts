import { Redis } from 'ioredis';
import {
  realtimeEventSchema,
  type RealtimeEvent,
  type SequencedRealtimeEvent
} from '@pulsemesh/realtime';
import { config } from '../config.js';

export const redis = new Redis(config.REDIS_URL, {
  maxRetriesPerRequest: 2
});

export const publisher = new Redis(config.REDIS_URL, {
  maxRetriesPerRequest: 2
});

export const subscriber = new Redis(config.REDIS_URL, {
  maxRetriesPerRequest: null
});

export const queueRedis = new Redis(config.REDIS_URL, {
  maxRetriesPerRequest: null
});

export const REALTIME_CHANNEL = 'pulsemesh:events';

const REALTIME_SEQUENCE_KEY = 'pulsemesh:realtime:sequence';
const RECOVERY_PREFIX = 'pulsemesh:realtime:recovery:';
const RECOVERY_TTL_SECONDS = 15 * 60;
const RECOVERY_EVENTS_PER_ROOM = 2_000;

function recoveryKey(room: string): string {
  return RECOVERY_PREFIX + room;
}

export async function publishRealtime(
  event: RealtimeEvent
): Promise<SequencedRealtimeEvent> {
  const sequence = await publisher.incr(REALTIME_SEQUENCE_KEY);
  const enriched = { ...event, sequence } as SequencedRealtimeEvent;
  const serialized = JSON.stringify(enriched);
  const key = recoveryKey(event.room);

  const script = [
    "redis.call('ZADD', KEYS[1], ARGV[1], ARGV[2])",
    "redis.call('EXPIRE', KEYS[1], ARGV[3])",
    "local count = redis.call('ZCARD', KEYS[1])",
    "local maxItems = tonumber(ARGV[4])",
    "if count > maxItems then",
    "  redis.call('ZREMRANGEBYRANK', KEYS[1], 0, count - maxItems - 1)",
    "end",
    "return count"
  ].join('\n');

  await publisher.eval(
    script,
    1,
    key,
    sequence,
    serialized,
    RECOVERY_TTL_SECONDS,
    RECOVERY_EVENTS_PER_ROOM
  );
  await publisher.publish(REALTIME_CHANNEL, serialized);
  return enriched;
}

export async function publishEphemeralRealtime(
  event: RealtimeEvent
): Promise<void> {
  await publisher.publish(REALTIME_CHANNEL, JSON.stringify(event));
}

export async function latestRealtimeSequence(): Promise<number> {
  const value = await redis.get(REALTIME_SEQUENCE_KEY);
  return value ? Number(value) : 0;
}

export async function replayRealtimeEvents(input: {
  rooms: string[];
  afterSequence: number;
  throughSequence: number;
  limit?: number;
}): Promise<{ events: SequencedRealtimeEvent[]; truncated: boolean }> {
  const limit = input.limit ?? 500;
  if (input.rooms.length === 0 || input.throughSequence <= input.afterSequence) {
    return { events: [], truncated: false };
  }

  const merged = new Map<string, SequencedRealtimeEvent>();
  const perRoomLimit = limit + 1;

  for (const room of input.rooms) {
    const rawEvents = await redis.zrangebyscore(
      recoveryKey(room),
      '(' + String(input.afterSequence),
      String(input.throughSequence),
      'LIMIT',
      0,
      perRoomLimit
    );

    for (const raw of rawEvents) {
      let value: unknown;
      try {
        value = JSON.parse(raw);
      } catch {
        continue;
      }

      const parsed = realtimeEventSchema.safeParse(value);
      if (!parsed.success || typeof parsed.data.sequence !== 'number') continue;
      if (parsed.data.sequence > input.throughSequence) continue;
      merged.set(parsed.data.id, parsed.data as SequencedRealtimeEvent);
    }
  }

  const sorted = [...merged.values()].sort((left, right) => left.sequence - right.sequence);
  return {
    events: sorted.slice(0, limit),
    truncated: sorted.length > limit
  };
}
