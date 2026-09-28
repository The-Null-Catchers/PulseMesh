# Realtime

WebSockets carry live events. REST carries durable commands, pagination and recovery.

Shared contracts live in packages/realtime. Server events have a unique event ID, event type, authorized room, server timestamp and typed payload.

Rooms use workspace, channel and conversation namespaces. A client request never grants itself access; room membership is checked by the server.

API replicas publish committed state changes to Redis Pub/Sub. Every replica consumes the same channel and forwards an event only to locally connected sockets subscribed to that room.

Presence keys expire automatically. Heartbeats extend their TTL. Typing state is never persisted.

After reconnect, clients obtain a new one-time ticket, reconnect with exponential backoff, re-subscribe and incrementally synchronize messages over REST. Realtime arrival order is not trusted. Clients deduplicate by message ID and reconcile optimistic sends with client_message_id.
