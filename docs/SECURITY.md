# Security

Passwords use Argon2id. Access JWTs are short-lived. Refresh tokens rotate on every use and the current hash plus generation is stored on the session. A stale or mismatched refresh token revokes its session family.

Users can view and revoke device sessions or log out from every device.

Authorization is enforced through service-layer permission checks. Client permission claims are never trusted.

WebSockets use a random one-time ticket with a 30 second lifetime. Each room subscription is authorized independently.

Rich content must be sanitized before rendering. Link-preview workers must block private, loopback, link-local and metadata-network targets, limit redirects and response size, and validate every redirect destination.

Uploads use signed S3 requests. Workers should verify detected MIME type and dimensions before marking media ready.

Optional E2EE must use established cryptographic protocols and maintained libraries. The server can still observe delivery metadata, participants, timing, ciphertext size and encrypted attachment metadata; private keys must not be stored server-side in plaintext.
