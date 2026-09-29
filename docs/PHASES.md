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

Implemented in the Phase 3 hardening slice:

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

Foundation already exists:

- signed S3-compatible uploads
- MinIO local storage
- file metadata model
- BullMQ notification worker
- in-app notification data model and preferences

Next work:

- image thumbnail and preview jobs
- attachment finalization and validation
- link preview worker with SSRF protection
- voice-message processing
- FCM and Web Push delivery
- duplicate-suppression rules for actively viewed conversations

## Phases 5–8

The WebRTC, offline sync, moderation, E2EE and observability documents define stable boundaries for subsequent PRs. Each phase should land only after CI for the previous slice is green so the repository remains deployable and reviewable.
