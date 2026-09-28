# Implementation Phases

PulseMesh evolves in buildable slices rather than one oversized feature dump.

## Phase 1 — Foundation

Implemented in PR #1:

- monorepo and shared contracts
- PostgreSQL, Redis, MinIO and Coturn development environment
- authentication, verification and device sessions
- workspace model and reusable RBAC service
- polished web and mobile shells

## Phase 2 — Core Messaging

Working slices included in PR #1:

- text channels
- direct and group conversations
- cursor history
- optimistic idempotency through client_message_id
- replies
- edit history
- soft deletion
- reactions
- efficient read state

Threads, pins, forwarding and bookmarks extend these message primitives.

## Phase 3 — Realtime

Working slices included in PR #1:

- one-time WebSocket tickets
- authorized room subscriptions
- Redis Pub/Sub fanout across API replicas
- typing events
- heartbeat presence foundation
- reconnect model documented around REST reconciliation

Per-device presence aggregation and richer recovery metadata remain follow-up work.

## Phase 4 — Files and Notifications

Foundation included in PR #1:

- signed S3-compatible uploads
- MinIO local storage
- file metadata model
- BullMQ notification worker
- in-app notification data model and preferences

Thumbnail, audio, push and Web Push processors remain follow-up jobs.

## Phases 5–8

The WebRTC, offline sync, moderation, E2EE and observability documents define stable boundaries for subsequent PRs. These features should be implemented after the foundation CI is green so each phase remains reviewable and deployable.
