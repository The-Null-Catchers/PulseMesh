# Security

Passwords use Argon2id. Access JWTs are short-lived. Refresh tokens rotate on every use and the current hash plus generation is stored on the session. A stale or mismatched refresh token revokes its session family.

Users can view and revoke device sessions or log out from every device.

Authorization is enforced through service-layer permission checks. Client permission claims are never trusted.

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

Optional E2EE must use established cryptographic protocols and maintained libraries. The server can still observe delivery metadata, participants, timing, ciphertext size and encrypted attachment metadata; private keys must not be stored server-side in plaintext.
