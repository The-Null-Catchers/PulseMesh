# Architecture

PulseMesh separates durable state, realtime state, asynchronous work and media transport.

## Durable path

PostgreSQL is authoritative for users, sessions, workspaces, roles, channels, conversations, messages, files, calls, notifications, moderation and audit logs. Commands commit database changes before publishing realtime events.

## Realtime path

Each API instance hosts WebSocket clients. Redis Pub/Sub fans events between replicas. Connections subscribe only to rooms that the server authorizes against durable membership. Presence, typing, reconnect replay buffers and active-view hints are ephemeral Redis state.

Clients acquire a short-lived one-time WebSocket ticket through authenticated REST. The ticket is consumed atomically on connect so a long-lived access token does not need to be placed in a WebSocket URL.

## File path

The API creates file metadata and returns a signed S3-compatible PUT URL. Object bytes bypass API and WebSocket processes. Completion verifies object metadata, then a BullMQ worker validates magic bytes and produces derived media such as thumbnails. Only `ready` files may be attached to a message. Attachments are committed in the same PostgreSQL transaction as the message.

Authorized clients receive short-lived signed download or thumbnail URLs. This model works with MinIO locally and R2/S3-compatible storage in production.

## Notification path

Creating a durable notification enqueues a BullMQ delivery job. The worker evaluates quiet hours, mute state, DND and the Redis active-view hint before sending external delivery.

Supported delivery surfaces are:

- durable in-app notification rows
- Firebase Cloud Messaging
- Web Push with VAPID
- SMTP email for security messages and mentions

Invalid push endpoints are disabled rather than retried forever. The database remains the durable record even when a provider is unavailable.

## Module boundaries

- auth: credentials, verification, rotating sessions
- workspaces: membership and roles
- authorization: reusable permission decisions
- channels: channel lifecycle
- conversations: direct and group conversations
- messages: durable message state, attachments, edits, reactions and threads
- realtime: sockets, fanout, recovery, typing and presence
- files: S3 metadata, verification and signed transfers
- notifications: in-app, push and email policy
- calls: signaling session state and media-provider boundaries
- moderation: reports and enforcement
- worker: asynchronous notification and media jobs

## Scaling

API and worker processes scale horizontally. Redis coordinates ephemeral state and queues. PostgreSQL remains the durable source of truth. Object bytes live outside PostgreSQL. Sticky HTTP sessions are not required.

## Failure model

Database outage blocks durable writes. Redis outage degrades realtime fanout, recovery hints and jobs without invalidating committed data. WebSocket reconnect performs replay and REST reconciliation. Duplicate offline sends are absorbed by the sender plus `client_message_id` uniqueness rule.

The monolith is modular first. Search, notification, file and signaling services can be extracted later behind existing boundaries when operational need justifies the cost.
