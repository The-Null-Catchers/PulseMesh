import type { FastifyInstance } from 'fastify';
import websocket from '@fastify/websocket';
import { randomUUID } from 'node:crypto';
import {
  clientRealtimeMessageSchema,
  realtimeEventSchema,
  type RealtimeEvent,
  type SequencedRealtimeEvent
} from '@pulsemesh/realtime';
import {
  canAccessChannel,
  canAccessConversation,
  isWorkspaceMember
} from '../authorization/service.js';
import {
  REALTIME_CHANNEL,
  latestRealtimeSequence,
  publishRealtime,
  redis,
  replayRealtimeEvents,
  subscriber
} from './bus.js';
import { consumeRealtimeTicket } from './tickets.js';
import {
  broadcastPresence,
  disconnectPresence,
  sweepExpiredPresence,
  touchPresence
} from '../presence/service.js';

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
  recoveringThrough: number | null;
  pendingEvents: SequencedRealtimeEvent[];
}

const connections = new Set<Connection>();
const TYPING_TTL_MS = 8_000;
const MAX_PENDING_RECOVERY_EVENTS = 1_000;

async function canAccessRoom(userId: string, room: string): Promise<boolean> {
  const [kind, id] = room.split(':');
  if (!id) return false;
  if (kind === 'channel') return canAccessChannel(userId, id);
  if (kind === 'conversation') return canAccessConversation(userId, id);
  if (kind === 'workspace') return isWorkspaceMember(userId, id);
  return false;
}

function send(connection: Connection, value: unknown): void {
  if (connection.socket.readyState !== connection.socket.OPEN) return;
  connection.socket.send(JSON.stringify(value));
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
        !connection.rooms.has(parsed.data.room) ||
        connection.socket.readyState !== connection.socket.OPEN
      ) {
        continue;
      }

      if (
        connection.recoveringThrough !== null &&
        typeof parsed.data.sequence === 'number'
      ) {
        if (parsed.data.sequence <= connection.recoveringThrough) continue;

        if (connection.pendingEvents.length >= MAX_PENDING_RECOVERY_EVENTS) {
          connection.socket.close(1013, 'Recovery buffer overflow');
          continue;
        }

        connection.pendingEvents.push(parsed.data as SequencedRealtimeEvent);
        continue;
      }

      connection.socket.send(JSON.stringify(parsed.data));
    }
  });

  const sweeper = setInterval(() => {
    void sweepExpiredPresence().catch((error: unknown) => {
      app.log.error({ err: error }, 'presence sweeper failed');
    });
  }, 10_000);
  sweeper.unref();
  app.addHook('onClose', async () => {
    clearInterval(sweeper);
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
      rooms: new Set(),
      recoveringThrough: null,
      pendingEvents: []
    };
    connections.add(connection);

    const becameOnline = await touchPresence(identity.userId, identity.sessionId);
    if (becameOnline) await broadcastPresence(identity.userId);

    send(connection, {
      type: 'session.ready',
      occurredAt: new Date().toISOString(),
      latestSequence: await latestRealtimeSequence()
    });

    socket.on('message', async (raw: unknown) => {
      let value: unknown;
      try {
        value = JSON.parse(typeof raw === 'string' ? raw : String(raw));
      } catch {
        return;
      }

      const parsed = clientRealtimeMessageSchema.safeParse(value);
      if (!parsed.success) return;

      if (parsed.data.type === 'presence.heartbeat') {
        const returnedOnline = await touchPresence(identity.userId, identity.sessionId);
        if (returnedOnline) await broadcastPresence(identity.userId);
        return;
      }

      if (parsed.data.type === 'session.resume') {
        const rooms = [...new Set(parsed.data.rooms)];
        const authorizedRooms: string[] = [];
        for (const room of rooms) {
          if (await canAccessRoom(identity.userId, room)) {
            authorizedRooms.push(room);
          }
        }

        connection.rooms.clear();
        for (const room of authorizedRooms) connection.rooms.add(room);

        const throughSequence = await latestRealtimeSequence();
        connection.recoveringThrough = throughSequence;

        const replay = await replayRealtimeEvents({
          rooms: authorizedRooms,
          afterSequence: parsed.data.lastSequence,
          throughSequence,
          limit: 500
        });

        for (const event of replay.events) send(connection, event);

        connection.pendingEvents.sort(
          (left, right) => left.sequence - right.sequence
        );
        for (const event of connection.pendingEvents.splice(0)) {
          send(connection, event);
        }
        connection.recoveringThrough = null;

        send(connection, {
          type: 'session.resumed',
          occurredAt: new Date().toISOString(),
          latestSequence: await latestRealtimeSequence(),
          replayedCount: replay.events.length,
          truncated: replay.truncated
        });
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

      if (parsed.data.type === 'typing.started') {
        const expiresAt = new Date(Date.now() + TYPING_TTL_MS).toISOString();
        await redis.set(
          'typing:' + parsed.data.room + ':' + identity.userId,
          '1',
          'PX',
          TYPING_TTL_MS
        );
        const event: RealtimeEvent = {
          id: randomUUID(),
          type: 'typing.started',
          room: parsed.data.room,
          occurredAt: new Date().toISOString(),
          payload: { userId: identity.userId, expiresAt }
        };
        await publishRealtime(event);
        return;
      }

      await redis.del('typing:' + parsed.data.room + ':' + identity.userId);
      const event: RealtimeEvent = {
        id: randomUUID(),
        type: 'typing.stopped',
        room: parsed.data.room,
        occurredAt: new Date().toISOString(),
        payload: { userId: identity.userId, expiresAt: null }
      };
      await publishRealtime(event);
    });

    socket.on('close', () => {
      connections.delete(connection);
      void disconnectPresence(identity.userId, identity.sessionId)
        .then(async (becameOffline) => {
          if (becameOffline) await broadcastPresence(identity.userId);
        })
        .catch((error: unknown) => {
          app.log.error({ err: error }, 'presence disconnect failed');
        });
    });
  });
}

export function activeWebSocketConnections(): number {
  return connections.size;
}
