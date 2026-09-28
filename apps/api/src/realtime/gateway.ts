import type { FastifyInstance } from 'fastify';
import websocket from '@fastify/websocket';
import { randomUUID } from 'node:crypto';
import { clientRealtimeMessageSchema, realtimeEventSchema, type RealtimeEvent } from '@pulsemesh/realtime';
import { canAccessChannel, canAccessConversation, isWorkspaceMember } from '../authorization/service.js';
import { REALTIME_CHANNEL, publishRealtime, redis, subscriber } from './bus.js';
import { consumeRealtimeTicket } from './tickets.js';

interface SocketLike {
  OPEN: number;
  readyState: number;
  send(data: string): void;
  close(code?: number, reason?: string): void;
  on(event: string, handler: (...args: any[]) => void): void;
}

interface Connection {
  socket: SocketLike;
  userId: string;
  rooms: Set<string>;
}

const connections = new Set<Connection>();

async function canAccessRoom(userId: string, room: string): Promise<boolean> {
  const [kind, id] = room.split(':');
  if (!id) return false;
  if (kind === 'channel') return canAccessChannel(userId, id);
  if (kind === 'conversation') return canAccessConversation(userId, id);
  if (kind === 'workspace') return isWorkspaceMember(userId, id);
  return false;
}

async function heartbeat(userId: string): Promise<void> {
  await redis.set('presence:user:' + userId, 'online', 'EX', 70);
}

export async function registerRealtimeGateway(app: FastifyInstance): Promise<void> {
  await app.register(websocket);

  await subscriber.subscribe(REALTIME_CHANNEL);
  subscriber.on('message', (_channel, raw) => {
    let json: unknown;
    try {
      json = JSON.parse(raw);
    } catch {
      return;
    }
    const parsed = realtimeEventSchema.safeParse(json);
    if (!parsed.success) return;

    for (const connection of connections) {
      if (
        connection.rooms.has(parsed.data.room) &&
        connection.socket.readyState === connection.socket.OPEN
      ) {
        connection.socket.send(JSON.stringify(parsed.data));
      }
    }
  });

  app.get('/realtime', { websocket: true }, async (socket, request) => {
    const ticket = (request.query as { ticket?: string }).ticket;
    if (!ticket) {
      socket.close(4401, 'Missing ticket');
      return;
    }

    const identity = await consumeRealtimeTicket(ticket);
    if (!identity) {
      socket.close(4401, 'Invalid or expired ticket');
      return;
    }

    const connection: Connection = {
      socket: socket as unknown as SocketLike,
      userId: identity.userId,
      rooms: new Set()
    };
    connections.add(connection);
    await heartbeat(identity.userId);

    socket.send(JSON.stringify({
      type: 'session.ready',
      occurredAt: new Date().toISOString()
    }));

    socket.on('message', async (raw) => {
      let value: unknown;
      try {
        value = JSON.parse(raw.toString());
      } catch {
        return;
      }
      const parsed = clientRealtimeMessageSchema.safeParse(value);
      if (!parsed.success) return;

      if (parsed.data.type === 'presence.heartbeat') {
        await heartbeat(identity.userId);
        return;
      }

      if (parsed.data.type === 'room.subscribe') {
        if (await canAccessRoom(identity.userId, parsed.data.room)) {
          connection.rooms.add(parsed.data.room);
        }
        return;
      }

      if (parsed.data.type === 'room.unsubscribe') {
        connection.rooms.delete(parsed.data.room);
        return;
      }

      if (!connection.rooms.has(parsed.data.room)) return;
      const event: RealtimeEvent = {
        id: randomUUID(),
        type: parsed.data.type,
        room: parsed.data.room,
        occurredAt: new Date().toISOString(),
        payload: { userId: identity.userId }
      };
      await publishRealtime(event);
    });

    socket.on('close', () => {
      connections.delete(connection);
      void redis.del('presence:user:' + identity.userId);
    });
  });
}

export function activeWebSocketConnections(): number {
  return connections.size;
}
