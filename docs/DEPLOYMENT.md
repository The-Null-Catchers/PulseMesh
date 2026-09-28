# Deployment

Recommended production topology:

    Caddy
      -> web replicas
      -> API replicas
           -> PostgreSQL
           -> Redis
           -> S3 or R2
           -> worker replicas
      -> Coturn

Typical domains are pulsemesh.example.com and api.pulsemesh.example.com. Caddy proxies WebSocket upgrades automatically.

Never commit JWT secrets, database credentials, S3 keys, SMTP passwords or TURN credentials.

Release sequence:

1. build immutable images
2. run CI
3. back up state when migration risk warrants it
4. run migrations once
5. deploy workers
6. deploy API replicas
7. deploy web
8. verify liveness and readiness
9. watch errors, queue depth and WebSocket counts

TURN needs TCP and UDP 3478 plus the configured UDP relay range. Production behind NAT must configure external address mapping correctly.

API replicas do not require sticky HTTP sessions. Redis Pub/Sub distributes realtime events. Worker concurrency scales through BullMQ.
