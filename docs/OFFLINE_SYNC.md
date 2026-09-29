# Offline Sync

PulseMesh mobile uses SQLite through `sqflite` as a durable local cache and outgoing queue. PostgreSQL remains authoritative; the phone database is a synchronization replica optimized for recent data and optimistic UX.

## Local state

The mobile cache stores:

- recent messages keyed by stable local IDs plus optional server IDs
- generic cached workspace, channel, conversation and user payloads
- one synchronization cursor per channel or conversation
- an outgoing message queue with retry state

Every offline send gets a client-generated UUID. That UUID is persisted before any network request, rendered immediately as `sending`, and sent to the API as `clientMessageId`. The server uniqueness constraint on sender + client ID makes retries idempotent.

A successful acknowledgement attaches the server message ID and authoritative server timestamp to the existing optimistic row. Permanent validation/authorization failures become `failed` entries that can be retried explicitly. Transient failures use capped exponential backoff.

## Race-safe bootstrap

A new room cache does not replay the complete conversation journal.

1. The client asks for the room's current sync high-water cursor.
2. The client fetches a recent page of message history.
3. Both are committed locally in one SQLite transaction.
4. Incremental sync resumes strictly after the captured cursor.

The cursor is captured before recent history is fetched. A message created during that window is therefore either already included in the history response or returned by the incremental journal afterwards. Local upserts deduplicate both paths.

## Incremental reconciliation

The API keeps a durable PostgreSQL `message_sync_events` journal. Global message changes advance every client cursor. Delete-for-self operations create user-targeted tombstones. Events targeted at another user are never returned as visible changes, but the raw cursor still advances past them so clients do not repeatedly scan unrelated events.

Each sync page is applied together with its new cursor inside one SQLite transaction. A crash can therefore cause a page to replay, but cannot advance the cursor without applying the page. Replays are safe because server IDs and client-generated IDs are unique.

Realtime WebSocket delivery is an acceleration path, not the durability mechanism. After reconnect, the client restores the WebSocket session and then uses REST cursor synchronization to repair anything missed while disconnected.

## Ordering and connectivity

Optimistic messages use a local timestamp only until acknowledgement. Canonical ordering uses server timestamps and server IDs after acknowledgement.

`connectivity_plus` is used only as a trigger to attempt synchronization. A reported Wi-Fi or cellular connection is never treated as proof of internet reachability; network requests still handle timeouts, HTTP failures and captive-portal conditions normally.

Large file bytes are not queued inside SQLite or sent through WebSockets. Existing uploaded attachment IDs may travel with a pending message; future resumable upload work should use the object-storage multipart boundary.
