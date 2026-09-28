# Architecture

PulseMesh separates durable state, realtime state, asynchronous work and media transport.

## Durable path

PostgreSQL is authoritative for users, sessions, workspaces, roles, channels, conversations, messages, files, calls, notifications, moderation and audit logs. Commands commit database changes before publishing realtime events.

## Realtime path

Each API instance hosts WebSocket clients. Redis Pub/Sub fans events between replicas. Connections subscribe only to rooms that the server authorizes against durable membership. Presence and typing are ephemeral Redis state.

Clients acquire a short-lived one-time WebSocket ticket through authenticated REST. The ticket is consumed atomically on connect so a long-lived access token does not need to be placed in a WebSocket URL.

## Module boundaries

- auth: credentials, verification, rotating sessions
- workspaces: membership and roles
- authorization: reusable permission decisions
- channels: channel lifecycle
- conversations: direct and group conversations
- messages: durable message state, edits, reactions and threads
- realtime: sockets, fanout, typing and presence
- files: S3 metadata and signed transfers
- notifications: in-app, push and email policy
- calls: signaling session state and media-provider boundaries
- moderation: reports and enforcement
- worker: asynchronous jobs

## Scaling

API and worker processes scale horizontally. Redis coordinates ephemeral state and queues. PostgreSQL remains the durable source of truth. Object bytes live outside PostgreSQL. Sticky HTTP sessions are not required.

## Failure model

Database outage blocks durable writes. Redis outage degrades realtime fanout and jobs without invalidating committed data. WebSocket reconnect performs REST reconciliation. Duplicate offline sends are absorbed by the sender plus client_message_id uniqueness rule.

The monolith is modular first. Search, notification, file and signaling services can be extracted later behind existing boundaries when operational need justifies the cost.
