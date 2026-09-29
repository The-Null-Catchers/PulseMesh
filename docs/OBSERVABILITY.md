# Observability

PulseMesh exposes Prometheus-compatible metrics at `GET /metrics`.

Set `METRICS_TOKEN` in production to require a bearer token for scraping. The endpoint exports no user IDs, workspace IDs, channel IDs or message text as labels.

## Metrics

The API exports Node.js process/default metrics plus:

- `pulsemesh_http_requests_total`
- `pulsemesh_http_errors_total`
- `pulsemesh_http_request_duration_seconds`
- `pulsemesh_messages_created_total`
- `pulsemesh_websocket_connections`
- `pulsemesh_connected_users`
- `pulsemesh_job_queue_depth`

HTTP labels use the Fastify route template rather than raw URLs, which bounds cardinality. Message throughput can be measured with a Prometheus `rate()` over the monotonic message counter. WebSocket connections are per API instance; Prometheus should aggregate across replicas.

Queue depth is collected from BullMQ at scrape time for notification and file queues. Connected users are counted from the unexpired Redis presence index; this is operational state, not a replacement for PostgreSQL user records.

## Logs and request correlation

Fastify structured JSON logs remain the primary request log. Incoming `x-request-id` is honored and generated IDs are returned in consistent API error envelopes.

Do not log access tokens, refresh tokens, E2EE private key material, plaintext from encrypted conversations, push subscription secrets or signed object-storage URLs.

## Suggested alerts

Production deployments should alert on sustained conditions rather than single samples:

- elevated 5xx error rate
- p95/p99 request latency regression
- notification/file queue backlog growth
- repeated worker failures
- Redis/PostgreSQL readiness failures
- unexpected WebSocket connection drops
- disk/object-storage capacity thresholds

Prometheus and Grafana are not mandatory runtime dependencies of PulseMesh; the API exposes the standard scrape surface so operators can use an existing monitoring stack.
