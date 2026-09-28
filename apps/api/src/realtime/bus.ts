import Redis from 'ioredis';
import type { RealtimeEvent } from '@pulsemesh/realtime';
import { config } from '../config.js';

export const redis = new Redis(config.REDIS_URL, { maxRetriesPerRequest: 2 });
export const publisher = new Redis(config.REDIS_URL, { maxRetriesPerRequest: 2 });
export const subscriber = new Redis(config.REDIS_URL, { maxRetriesPerRequest: null });
export const queueRedis = new Redis(config.REDIS_URL, { maxRetriesPerRequest: null });

export const REALTIME_CHANNEL = 'pulsemesh:events';

export async function publishRealtime(event: RealtimeEvent): Promise<void> {
  await publisher.publish(REALTIME_CHANNEL, JSON.stringify(event));
}
