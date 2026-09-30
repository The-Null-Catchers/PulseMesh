# Realtime

PulseMesh uses WebSockets for live state and REST for durable CRUD, pagination, and authoritative reconciliation.

## Event contract

Shared contracts live in `packages/realtime`. Every published server event carries:

- a UUID event ID
- an authorized room
- a server timestamp
- a Redis-assigned monotonic sequence
- a typed payload

Clients never choose authorization. Subscribing to `workspace:<id>`, `channel:<id>`, or `conversation:<id>` triggers a server-side access check.

## Multi-replica fanout

Committed state changes are published through Redis Pub/Sub. Every API replica consumes the same channel and forwards events only to locally connected sockets subscribed to the authorized room.

PostgreSQL remains the durable source of truth. Redis is coordination and short-lived recovery infrastructure only.

## User inbox signals

Every authenticated socket is implicitly subscribed to its private `user:<id>` room. Message creation publishes a lightweight `inbox.message` signal to authorized recipients on that private room, including the destination ID, message ID, sender ID, and server timestamp but not message content.

This lets clients refresh unread summaries for inactive channels and conversations without subscribing to every destination room. Inbox signals are recoverable through the same bounded Redis replay mechanism, while unread counts remain authoritative in PostgreSQL through `read_states`.

## Session recovery

Published events are also kept in a bounded per-room Redis sorted set for 15 minutes. The sequence is the score.

After a reconnect the client obtains a new one-time WebSocket ticket and sends:

```json
{
  "type": "session.resume",
  "lastSequence": 1204,
  "rooms": ["workspace:...", "channel:..."]
}
```

The gateway re-authorizes every requested room, snapshots the current upper sequence, replays matching events through that upper bound, buffers newer events during replay, then emits `session.resumed`.

Replay is capped. If a client is outside the Redis recovery window, or a replay is truncated, it must reconcile durable state through cursor-based REST synchronization. Clients always deduplicate by event ID and message ID and reconcile optimistic sends with `client_message_id`.

## Presence

Presence is aggregated by authenticated session rather than a single user key.

Each connected session refreshes a sorted-set lease with a 70-second TTL. The effective user state is:

- `offline` when no unexpired device sessions exist
- otherwise the persisted user preference: `online`, `idle`, or `do-not-disturb`

Custom status text and the preferred presence mode are durable PostgreSQL profile state. Active workspace and device leases are ephemeral Redis state. A distributed expiry index allows API replicas to detect stale users and publish an offline transition without treating Redis as durable storage.

Workspace members can fetch an initial presence snapshot over REST and then consume `presence.updated` events.

## Typing

Typing indicators are ephemeral. A `typing.started` event includes an `expiresAt` timestamp eight seconds in the future and Redis stores only a temporary key. Clients must remove the indicator at expiry even if a matching `typing.stopped` packet is lost.

## Client SDK

`@pulsemesh/sdk` includes a WebSocket client that:

- obtains one-time tickets
- reconnects with exponential backoff and jitter
- remembers room subscriptions
- resumes from the last sequence
- deduplicates recently seen events
- exposes connection-state and sequence callbacks
