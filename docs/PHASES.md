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

- one-time WebSocket tickets
- authorized room subscriptions
- Redis Pub/Sub fanout across API replicas
- monotonic server event sequence
- bounded per-room reconnect replay
- replay buffering so live packets do not interleave with recovered history
- multi-device presence leases
- persisted custom presence preference
- workspace presence snapshots
- distributed offline expiry detection
- typing TTL and client-side expiry contract
- reconnecting SDK with exponential backoff, room restoration and deduplication

Durable REST synchronization remains the final fallback when the temporary replay window cannot cover a disconnect.

## Phase 4 — Files and Notifications

Implemented:

- signed S3-compatible uploads and MinIO development storage
- explicit MIME allowlist and per-category size limits
- object-size, metadata and content-type verification after direct upload
- BullMQ file finalization with retry/backoff
- magic-byte MIME validation before a file becomes usable
- image dimensions and WebP thumbnail generation
- atomic attachment-to-message transactions
- attachment metadata in paginated message history
- short-lived authorized download and thumbnail URLs
- in-app notification records and scoped preferences
- channel, workspace and conversation notification policy
- FCM mobile device registration and delivery
- Web Push subscription registration and VAPID delivery
- mention email delivery when SMTP is configured
- quiet hours, mute and do-not-disturb suppression
- active-view suppression so users do not receive duplicate external notifications while viewing the destination
- invalid mobile/web push endpoint deactivation

Link previews and richer audio/voice-message processing use the same worker and object-storage boundary and remain later media-processing slices.

## Phase 5 — Voice

Next:

- durable call sessions
- WebRTC signaling contracts
- Coturn credentials and ICE configuration
- voice-channel membership
- direct audio calls
- microphone mute/deafen and speaking state
- replaceable media-provider boundary for a future SFU

## Phases 6–8

Video/screen sharing, offline-first mobile synchronization, moderation, E2EE, observability and final hardening land as separate green-CI slices.
