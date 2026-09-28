# Offline Sync

The Flutter client is structured for a Drift local database containing recent workspaces, channels, conversations, users, messages and an outgoing queue.

Every offline send receives a client-generated UUID. The UI renders it immediately as sending. On connectivity restoration, the sync engine posts the same client_message_id. The server unique constraint turns retries into the same logical send.

The acknowledgement replaces optimistic identity with the server message ID and server timestamp. Permanent failures become retryable failed entries.

Reconnect refreshes authentication, obtains a fresh WebSocket ticket, re-subscribes to rooms and performs incremental REST synchronization. A complete history is never downloaded after every reconnect.

Canonical ordering comes from server timestamps and IDs. Realtime and REST results are deduplicated by message ID.
