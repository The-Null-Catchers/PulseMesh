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
- browser mesh media adapter
- Flutter mesh media adapter
- replaceable provider boundary for a future SFU

## Phase 6 — Video and Screen Sharing

Next:

- camera tracks
- browser screen capture
- active presenter state
- track replacement without restarting the call
- video-oriented call UI state recovery

## Phases 7–8

Offline-first mobile synchronization, moderation, E2EE, observability and final hardening land as separate green-CI slices.
