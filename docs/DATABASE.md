# Database

PostgreSQL is the permanent source of truth.

Messages use server timestamps plus UUID identifiers. Cursor pagination sorts by created_at and id. Offline clients send client_message_id; a partial unique index per sender makes retries idempotent.

Read receipts store one read_state per user and destination rather than one row per user-message pair.

Initial indexes cover sessions, membership, channel ordering, channel and conversation message cursors, threads, unread notifications, audit history and PostgreSQL full-text message search.

Presence and typing do not belong in PostgreSQL.

Search starts with PostgreSQL full-text search. The application boundary allows a later Meilisearch or Elasticsearch indexer to consume background jobs without changing message storage.

## Moderation and E2EE additions

Phase 8 adds durable moderation state without moving authority into Redis:

- `workspace_bans` records active/revoked workspace bans.
- `workspace_moderation_rules` stores durable anti-spam thresholds; Redis holds only short-lived counters.
- channel `locked_at/locked_by` fields make lock enforcement part of the normal authorization query.
- existing `reports`, `moderation_actions` and `audit_logs` tables remain the administrative history.

Optional one-to-one E2EE adds:

- conversation `encryption_mode` (`none` or `e2ee_v1`)
- message `encryption_version` and opaque `encrypted_payload`
- `e2ee_device_bundles` containing public identity/signed-prekey material per authenticated session
- `e2ee_one_time_prekeys` with transactional claim timestamps

No private cryptographic key or decrypted E2EE body belongs in PostgreSQL.

