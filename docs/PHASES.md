# Implementation Phases

PulseMesh evolves in buildable slices rather than one oversized feature dump.

## Phase 1 — Foundation

Implemented:

- monorepo and shared contracts
- PostgreSQL, Redis, MinIO and Coturn development environment
- authentication, verification and device sessions
- workspace model and reusable RBAC service
- polished web and mobile shells

## Phase 2 — Core Messaging

Implemented:

- text channels
- direct and group conversations
- cursor history
- optimistic idempotency through `client_message_id`
- replies and threads
- edit history
- soft deletion and delete-for-self
- reactions
- efficient read state
- pins, forwarding, bookmarks and channel preferences

## Phase 3 — Realtime

Implemented:

- one-time WebSocket tickets and authorized rooms
- Redis Pub/Sub fanout across API replicas
- reconnect sequence/replay
- multi-device presence
- typing TTL
- reconnecting SDK

## Phase 4 — Files and Notifications

Implemented:

- verified signed S3-compatible uploads
- worker MIME validation and image thumbnails
- atomic message attachments
- in-app, FCM, Web Push and mention email delivery
- scoped preferences, quiet hours, mute/DND rules
- active-view external-notification suppression

## Phase 5 — Voice

Implemented:

- durable call sessions and active per-device participants
- voice-channel and conversation audio calls
- short-lived TURN REST credentials
- targeted WebRTC signaling through private session rooms
- offer, answer and ICE contracts
- microphone mute/deafen state
- microphone selection
- ephemeral speaking state
- browser and Flutter mesh media adapters
- replaceable provider boundary for a future SFU

## Phase 6 — Video and Screen Sharing

Implemented:

- video calls for direct and group conversations
- camera capture and camera device switching on web and Flutter
- server-authoritative camera state
- browser screen capture with `getDisplayMedia`
- active presenter state through participant `screenSharing`
- video sender track replacement without restarting the call
- automatic camera restoration when screen capture ends
- realtime participant state recovery through durable call snapshots
- voice channels remain audio-only in the initial mesh provider

## Phase 7 — Offline Mobile

Implemented:

- SQLite recent-data cache for messages and workspace metadata
- persistent pending outgoing queue
- client-generated idempotency IDs
- authoritative acknowledgement timestamps and IDs
- durable PostgreSQL incremental message journal
- race-safe initial high-water cursor bootstrap
- delete-for-self user tombstones
- atomic page + cursor reconciliation
- reconnect repair without full-history downloads
- connectivity-triggered queue flush with capped retry backoff

## Phase 8 — Security and Polish

Implemented:

- reports and moderator queue APIs
- permission-gated timeout, kick, ban and channel lock operations
- audited moderator message deletion
- configurable Redis-backed anti-spam rules
- durable audit-log query API
- Prometheus-compatible request, message, WebSocket, presence and queue metrics
- optional protected metrics endpoint
- one-to-one E2EE server boundary with public device bundles and atomic one-time pre-key claims
- ciphertext-aware realtime and offline synchronization
- explicit metadata and limitation documentation

The E2EE boundary intentionally delegates cryptographic operations to established Signal Protocol libraries; PulseMesh does not ship custom cryptographic primitives.
