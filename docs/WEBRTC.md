# WebRTC

PulseMesh uses a replaceable media-session boundary. The initial provider is small-group mesh WebRTC; durable call membership lives in PostgreSQL while SDP, ICE candidates and speaking state remain ephemeral.

## Call lifecycle

A call belongs to exactly one voice channel or direct/group conversation.

The API persists:

- call ID, creator, kind, provider and timestamps
- active participant rows per authenticated device session
- mute, deafen, camera, screen-share and connection state

Workspace voice channels are audio-only in the initial mesh provider. Direct and group conversations may create voice or video calls.

The browser and Flutter clients both expose a mesh media-session adapter. The UI depends on that adapter rather than on raw `RTCPeerConnection` calls, so the provider can later move to LiveKit, mediasoup or Janus.

## Signaling

Signaling travels through the existing WebSocket gateway.

Each authenticated socket is automatically subscribed to:

- `user:<userId>`
- `session:<sessionId>`

Offers, answers and ICE candidates target a concrete call participant and are delivered only to its authenticated session room. They are not written to PostgreSQL, are not placed in the reconnect replay buffer, and are not broadcast to every member of a channel.

The sender must have an active participant row for the same call. Target participant membership is revalidated server-side.

Speaking state is an ephemeral room event with a short Redis TTL and is never replayed after reconnect.

## Camera and screen sharing

Camera tracks use the same peer connections established for audio. Switching camera devices replaces the outgoing video track rather than renegotiating an entirely new call.

On the web, screen sharing uses `navigator.mediaDevices.getDisplayMedia`. Starting a share replaces the current outgoing video track with the display track. When the browser or user stops capture, PulseMesh restores the camera track automatically when one exists.

The durable participant row exposes `cameraEnabled` and `screenSharing`, so reconnecting clients can reconstruct call UI state and identify the active presenter. Media bytes themselves remain peer-to-peer/TURN relayed and are never stored by the API.

Flutter supports camera capture and camera switching. Browser screen capture remains the Phase 6 screen-sharing surface because mobile screen capture needs platform-specific foreground-service/broadcast permissions.

## ICE and TURN

PulseMesh does not assume direct peer-to-peer connectivity.

Development Docker Compose runs Coturn. The API issues time-limited TURN REST credentials using HMAC-SHA1 and a server-side shared secret:

```text
expiry:userId
      ↓ HMAC(shared secret)
temporary TURN credential
```

The shared secret never goes to the client. Production should publish TURN over the required UDP/TCP/TLS endpoints and expose an appropriate relay range through the firewall.

`GET /calls/ice-config` returns the authenticated client's current ICE configuration.

## Initial mesh limits

Mesh is intentionally the first provider, not the permanent scaling model. Practical room size should remain small because upload bandwidth grows with each peer.

The provider boundary keeps these responsibilities outside chat persistence:

- microphone and camera capture
- speaker/deafen behavior
- device switching
- screen capture
- peer lifecycle
- offer/answer/ICE exchange
- remote media streams

When room sizes outgrow mesh, an SFU adapter can take over the same session and participant contracts.
