# Security

Passwords use Argon2id. Access JWTs are short-lived. Refresh tokens rotate on every use and the current hash plus generation is stored on the session. A stale or mismatched refresh token revokes its session family.

Users can view and revoke device sessions or log out from every device.

Authorization is enforced through service-layer permission checks. Client permission claims are never trusted. Moderation actions use the same permission service; controller routes do not bypass RBAC.

WebSockets use a random one-time ticket with a 30 second lifetime. Each room subscription and active-view destination is authorized independently. Active-view state is an expiring Redis hint used only to suppress redundant external notifications.

Rich content must be sanitized before rendering. Link-preview workers must block private, loopback, link-local and metadata-network targets, limit redirects and response size, and validate every redirect destination.

## Upload security

Clients upload bytes directly to S3-compatible storage using a short-lived signed PUT. A signed request does not make the object trusted.

Before PulseMesh allows a file to be attached:

1. the API verifies the object exists
2. expected size, object metadata and declared content type must match the signed request
3. the file worker reads magic bytes for binary formats
4. detected and declared MIME types must be compatible
5. images are decoded by Sharp before dimensions and thumbnails are accepted
6. only files in the `ready` state can be attached to messages

SVG is intentionally excluded from the initial image allowlist. Downloads and thumbnails require authorization and use short-lived signed GET URLs. Files are never transported through WebSocket messages.

## Notification security

FCM tokens and Web Push subscription secrets are never returned in full by device-list APIs. Delivery workers disable invalid endpoints. External delivery respects destination mute state, do-not-disturb, quiet hours, and an expiring active-view hint.

## Moderation and abuse controls

Workspace moderation is permission-gated through `moderation.manage`. Reports, moderator message deletion, member timeouts, kicks, bans, channel locks and policy changes create durable audit or moderation records.

Timeouts and channel locks are enforced in the same authorization path that decides whether a message may be sent. Anti-spam windows use Redis only for temporary counters; durable membership, rules, reports, bans and audit history remain in PostgreSQL.

The baseline rules limit burst messages, mention spam and repeated content. Redis scripts make each counter increment and TTL assignment atomic across API replicas.

## Optional direct-message E2EE

The initial E2EE boundary is limited to one-to-one conversations. PulseMesh does not implement a custom cryptographic protocol. Client implementations must delegate key agreement, authentication, ratcheting and message encryption to a maintained Signal Protocol implementation such as official libsignal bindings.

The server stores only public device material:

- public identity key
- public signed pre-key and its signature
- public one-time pre-keys
- non-secret registration and revision identifiers

One-time pre-keys are claimed transactionally with `FOR UPDATE SKIP LOCKED` so concurrent clients cannot consume the same pre-key. Private identity keys, private pre-keys, Signal session state and plaintext never belong in the API database.

When a direct conversation is switched to `e2ee_v1`, plaintext sends are rejected. New messages carry `libsignal-v1` opaque ciphertext, and the API does not run mentions, server-side full-text indexing or content moderation over that ciphertext. Encrypted messages are server-immutable in the initial release; deletion is still supported.

The server can still observe metadata including:

- conversation membership
- sender and recipient account/device identifiers
- message, delivery and read timing
- reply relationships
- ciphertext size
- device key revisions
- IP/session metadata already required for account security

Initial E2EE intentionally does not claim encrypted attachments, group E2EE, encrypted search or encrypted link previews. Those require dedicated client-side designs rather than silently exposing plaintext through existing server features.

Clients must persist peer identity keys and warn on unexpected identity-key changes. Server-provided public keys are transport data, not a substitute for peer authentication.
