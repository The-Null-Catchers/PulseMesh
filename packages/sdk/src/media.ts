import type { WebRtcSignal } from '@pulsemesh/realtime';

export interface MediaPeerState {
  participantId: string;
  connectionState: RTCPeerConnectionState;
}

export interface BrowserMeshMediaOptions {
  iceServers: RTCIceServer[];
  sendSignal: (
    targetParticipantId: string,
    signal: WebRtcSignal
  ) => void;
  onRemoteStream?: (
    participantId: string,
    stream: MediaStream
  ) => void;
  onPeerState?: (state: MediaPeerState) => void;
  onScreenShareEnded?: () => void;
}

export interface MediaSessionAdapter {
  startAudio(deviceId?: string): Promise<MediaStream>;
  startCamera(deviceId?: string): Promise<MediaStream>;
  startScreenShare(): Promise<MediaStream>;
  stopScreenShare(): Promise<void>;
  connectPeer(
    participantId: string,
    initiator: boolean
  ): Promise<void>;
  handleSignal(
    fromParticipantId: string,
    signal: WebRtcSignal
  ): Promise<void>;
  setMuted(muted: boolean): void;
  setDeafened(deafened: boolean): void;
  setCameraEnabled(enabled: boolean): void;
  selectMicrophone(deviceId: string): Promise<void>;
  selectCamera(deviceId: string): Promise<void>;
  leave(): void;
}

export class BrowserMeshMediaSession
  implements MediaSessionAdapter
{
  private audioTrack: MediaStreamTrack | null = null;
  private cameraTrack: MediaStreamTrack | null = null;
  private screenTrack: MediaStreamTrack | null = null;
  private readonly peers = new Map<
    string,
    RTCPeerConnection
  >();
  private readonly remoteStreams = new Map<
    string,
    MediaStream
  >();
  private deafened = false;

  constructor(
    private readonly options: BrowserMeshMediaOptions
  ) {}

  async startAudio(
    deviceId?: string
  ): Promise<MediaStream> {
    const stream =
      await navigator.mediaDevices.getUserMedia({
        audio: deviceId
          ? { deviceId: { exact: deviceId } }
          : true,
        video: false
      });
    const track = stream.getAudioTracks()[0];
    if (!track) {
      stream.getTracks().forEach((item) => item.stop());
      throw new Error('Microphone did not produce an audio track');
    }

    const wasMuted = this.audioTrack?.enabled === false;
    this.audioTrack?.stop();
    this.audioTrack = track;
    track.enabled = !wasMuted;

    await this.replaceTrackForAllPeers(
      'audio',
      track,
      stream
    );
    return stream;
  }

  async startCamera(
    deviceId?: string
  ): Promise<MediaStream> {
    const stream =
      await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: deviceId
          ? { deviceId: { exact: deviceId } }
          : true
      });
    const track = stream.getVideoTracks()[0];
    if (!track) {
      stream.getTracks().forEach((item) => item.stop());
      throw new Error('Camera did not produce a video track');
    }

    const wasDisabled =
      this.cameraTrack?.enabled === false;
    this.cameraTrack?.stop();
    this.cameraTrack = track;
    track.enabled = !wasDisabled;

    if (!this.screenTrack) {
      await this.replaceTrackForAllPeers(
        'video',
        track,
        stream
      );
    }

    return stream;
  }

  async startScreenShare(): Promise<MediaStream> {
    const stream =
      await navigator.mediaDevices.getDisplayMedia({
        video: true,
        audio: false
      });
    const track = stream.getVideoTracks()[0];
    if (!track) {
      stream.getTracks().forEach((item) => item.stop());
      throw new Error(
        'Screen capture did not produce a video track'
      );
    }

    this.screenTrack?.stop();
    this.screenTrack = track;
    track.addEventListener(
      'ended',
      () => {
        if (this.screenTrack !== track) return;
        void this.stopScreenShare().finally(() => {
          this.options.onScreenShareEnded?.();
        });
      },
      { once: true }
    );

    await this.replaceTrackForAllPeers(
      'video',
      track,
      stream
    );
    return stream;
  }

  async stopScreenShare(): Promise<void> {
    const track = this.screenTrack;
    this.screenTrack = null;
    if (track?.readyState !== 'ended') track?.stop();

    await this.replaceTrackForAllPeers(
      'video',
      this.cameraTrack,
      this.cameraTrack
        ? new MediaStream([this.cameraTrack])
        : null
    );
  }

  async connectPeer(
    participantId: string,
    initiator: boolean
  ): Promise<void> {
    const peer = this.ensurePeer(participantId);
    if (!initiator) return;

    const offer = await peer.createOffer();
    await peer.setLocalDescription(offer);

    if (offer.sdp) {
      this.options.sendSignal(participantId, {
        kind: 'offer',
        sdp: offer.sdp
      });
    }
  }

  async handleSignal(
    fromParticipantId: string,
    signal: WebRtcSignal
  ): Promise<void> {
    const peer = this.ensurePeer(fromParticipantId);

    if (signal.kind === 'offer') {
      await peer.setRemoteDescription({
        type: 'offer',
        sdp: signal.sdp
      });
      const answer = await peer.createAnswer();
      await peer.setLocalDescription(answer);
      if (answer.sdp) {
        this.options.sendSignal(fromParticipantId, {
          kind: 'answer',
          sdp: answer.sdp
        });
      }
      return;
    }

    if (signal.kind === 'answer') {
      await peer.setRemoteDescription({
        type: 'answer',
        sdp: signal.sdp
      });
      return;
    }

    await peer.addIceCandidate({
      candidate: signal.candidate,
      sdpMid: signal.sdpMid,
      sdpMLineIndex: signal.sdpMLineIndex,
      ...(signal.usernameFragment
        ? {
            usernameFragment:
              signal.usernameFragment
          }
        : {})
    });
  }

  setMuted(muted: boolean): void {
    if (this.audioTrack) {
      this.audioTrack.enabled = !muted;
    }
  }

  setDeafened(deafened: boolean): void {
    this.deafened = deafened;
    for (const stream of this.remoteStreams.values()) {
      stream.getAudioTracks().forEach((track) => {
        track.enabled = !deafened;
      });
    }
  }

  setCameraEnabled(enabled: boolean): void {
    if (this.cameraTrack) {
      this.cameraTrack.enabled = enabled;
    }
  }

  async selectMicrophone(
    deviceId: string
  ): Promise<void> {
    await this.startAudio(deviceId);
  }

  async selectCamera(
    deviceId: string
  ): Promise<void> {
    await this.startCamera(deviceId);
  }

  leave(): void {
    for (const peer of this.peers.values()) {
      peer.close();
    }
    this.peers.clear();

    for (const stream of this.remoteStreams.values()) {
      stream.getTracks().forEach((track) =>
        track.stop()
      );
    }
    this.remoteStreams.clear();

    this.audioTrack?.stop();
    this.cameraTrack?.stop();
    this.screenTrack?.stop();
    this.audioTrack = null;
    this.cameraTrack = null;
    this.screenTrack = null;
  }

  private activeVideoTrack(): MediaStreamTrack | null {
    return this.screenTrack ?? this.cameraTrack;
  }

  private ensurePeer(
    participantId: string
  ): RTCPeerConnection {
    const existing = this.peers.get(participantId);
    if (existing) return existing;

    const peer = new RTCPeerConnection({
      iceServers: this.options.iceServers
    });

    if (this.audioTrack) {
      peer.addTrack(
        this.audioTrack,
        new MediaStream([this.audioTrack])
      );
    }

    const videoTrack = this.activeVideoTrack();
    if (videoTrack) {
      peer.addTrack(
        videoTrack,
        new MediaStream([videoTrack])
      );
    }

    peer.onicecandidate = (event) => {
      if (!event.candidate) return;
      const candidate = event.candidate.toJSON();
      this.options.sendSignal(participantId, {
        kind: 'ice',
        candidate: candidate.candidate ?? '',
        sdpMid: candidate.sdpMid ?? null,
        sdpMLineIndex:
          candidate.sdpMLineIndex ?? null,
        ...(candidate.usernameFragment
          ? {
              usernameFragment:
                candidate.usernameFragment
            }
          : {})
      });
    };

    peer.ontrack = (event) => {
      const stream =
        event.streams[0] ?? new MediaStream([event.track]);
      this.remoteStreams.set(participantId, stream);
      stream.getAudioTracks().forEach((track) => {
        track.enabled = !this.deafened;
      });
      this.options.onRemoteStream?.(
        participantId,
        stream
      );
    };

    peer.onconnectionstatechange = () => {
      this.options.onPeerState?.({
        participantId,
        connectionState: peer.connectionState
      });
    };

    this.peers.set(participantId, peer);
    return peer;
  }

  private async replaceTrackForAllPeers(
    kind: 'audio' | 'video',
    track: MediaStreamTrack | null,
    stream: MediaStream | null
  ): Promise<void> {
    for (const peer of this.peers.values()) {
      const sender = peer
        .getSenders()
        .find(
          (candidate) =>
            candidate.track?.kind === kind ||
            (!candidate.track && kind === 'video')
        );

      if (sender) {
        await sender.replaceTrack(track);
      } else if (track && stream) {
        peer.addTrack(track, stream);
      }
    }
  }
}
