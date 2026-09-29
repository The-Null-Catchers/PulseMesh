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
- FCM, Web Push and SMTP notification delivery
- verified direct uploads with asynchronous media processing
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

REST carries durable CRUD and synchronization. WebSockets carry live events. API replicas fan out events through Redis Pub/Sub. A bounded Redis replay window supports fast session recovery, while PostgreSQL remains the source of truth.

File bytes move directly between clients and S3-compatible storage through signed URLs. Workers validate uploads before attachment, generate image thumbnails and handle asynchronous delivery. Notification workers support FCM, Web Push and email while respecting mute, quiet hours, DND and active-view suppression.

WebRTC signaling is kept behind a replaceable media boundary so initial small-group calls can later move to an SFU.

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
4. files and notifications — implemented
5. voice rooms — next
6. video and screen sharing
7. offline-first mobile synchronization
8. moderation, E2EE, observability and hardening
