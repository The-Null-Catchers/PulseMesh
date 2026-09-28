# Database

PostgreSQL is the permanent source of truth.

Messages use server timestamps plus UUID identifiers. Cursor pagination sorts by created_at and id. Offline clients send client_message_id; a partial unique index per sender makes retries idempotent.

Read receipts store one read_state per user and destination rather than one row per user-message pair.

Initial indexes cover sessions, membership, channel ordering, channel and conversation message cursors, threads, unread notifications, audit history and PostgreSQL full-text message search.

Presence and typing do not belong in PostgreSQL.

Search starts with PostgreSQL full-text search. The application boundary allows a later Meilisearch or Elasticsearch indexer to consume background jobs without changing message storage.
