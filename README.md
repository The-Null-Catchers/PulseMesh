# PulseMesh

PulseMesh is a production-oriented realtime communication platform for teams, communities, and developers. It is designed to demonstrate serious distributed systems engineering rather than a tutorial chat application.

## Repository

- Next.js web client
- Flutter mobile client
- Fastify TypeScript API
- PostgreSQL durable state
- Redis realtime coordination, reconnect recovery and BullMQ
- S3-compatible object storage with MinIO locally
- Coturn TURN/STUN
- Caddy reverse proxy
- shared realtime contracts and reconnecting SDK
- migrations, seed data, CI and architecture documentation

## Quick start

Requirements: Node.js 22+, pnpm 10+, Docker Compose, and Flutter for mobile.

    cp .env.example .env
    corepack enable
    pnpm install
    docker compose up -d postgres redis minio coturn
    pnpm --filter @pulsemesh/api db:migrate
    pnpm --filter @pulsemesh/api db:seed
    pnpm dev

Development endpoints:

- web: http://localhost:3000
- API: http://localhost:4000
- MinIO console: http://localhost:9001
- TURN: localhost:3478

Demo workspace: The Null Catchers

Demo users: Mohammed, Lama, Abdullah, Ibrahim, Shorouq

Development seed password: PulseMeshDemo123!

## Engineering model

REST carries durable CRUD and synchronization. WebSockets carry live events. API replicas fan out events through Redis Pub/Sub. A bounded Redis replay window supports fast session recovery, while PostgreSQL remains the source of truth. Presence is aggregated from expiring device-session leases. Files live in S3-compatible storage. Workers execute asynchronous notification and media jobs. WebRTC signaling is kept behind a replaceable media boundary so mesh calls can later move to an SFU.

Read the architecture notes in `docs/` before deploying.

## Architecture docs

- `docs/ARCHITECTURE.md`
- `docs/REALTIME.md`
- `docs/WEBRTC.md`
- `docs/DATABASE.md`
- `docs/SECURITY.md`
- `docs/OFFLINE_SYNC.md`
- `docs/DEPLOYMENT.md`
- `docs/PHASES.md`

## Roadmap

1. foundation — implemented
2. core messaging — implemented
3. realtime and presence — implemented
4. files and notifications — next
5. voice rooms
6. video and screen sharing
7. offline-first mobile synchronization
8. moderation, E2EE, observability and hardening
