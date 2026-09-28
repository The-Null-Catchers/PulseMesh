# WebRTC

Small initial calls use WebRTC with STUN and TURN. Coturn is included because peer-to-peer connectivity cannot be assumed.

The UI must depend on a media-session interface rather than directly on a concrete backend. The interface should expose join, leave, microphone, camera, screen share, mute, deafen, device selection, participant state and connection state.

Initial mesh signaling can travel through the PulseMesh realtime gateway. When group sizes outgrow mesh, that media adapter can move to an SFU such as LiveKit, mediasoup or Janus without changing chat persistence.

Production TURN requires public routing, a UDP relay range, strong credentials and preferably TLS-capable endpoints. Docker credentials are development-only.

Web screen sharing uses getDisplayMedia. Mobile capture is a separate native capability and should not be coupled to the browser implementation.
