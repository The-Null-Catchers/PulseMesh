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
}

export interface MediaSessionAdapter {
  startAudio(deviceId?: string): Promise<MediaStream>;
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
  selectMicrophone(deviceId: string): Promise<void>;
  leave(): void;
}

export class BrowserMeshMediaSession
  implements MediaSessionAdapter
{
  private localStream: MediaStream | null = null;
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
    this.localStream?.getTracks().forEach((track) =>
      track.stop()
    );
    this.localStream = stream;

    const track = stream.getAudioTracks()[0];
    if (track) {
      for (const peer of this.peers.values()) {
        const sender = peer
          .getSenders()
          .find(
            (candidate) =>
              candidate.track?.kind === 'audio'
          );
        if (sender) {
          await sender.replaceTrack(track);
        } else {
          peer.addTrack(track, stream);
        }
      }
    }

    return stream;
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
    this.localStream
      ?.getAudioTracks()
      .forEach((track) => {
        track.enabled = !muted;
      });
  }

  setDeafened(deafened: boolean): void {
    this.deafened = deafened;
    for (const stream of this.remoteStreams.values()) {
      stream.getAudioTracks().forEach((track) => {
        track.enabled = !deafened;
      });
    }
  }

  async selectMicrophone(
    deviceId: string
  ): Promise<void> {
    const muted =
      this.localStream?.getAudioTracks()[0]?.enabled ===
      false;
    const stream = await this.startAudio(deviceId);
    if (muted) {
      stream.getAudioTracks().forEach((track) => {
        track.enabled = false;
      });
    }
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

    this.localStream?.getTracks().forEach((track) =>
      track.stop()
    );
    this.localStream = null;
  }

  private ensurePeer(
    participantId: string
  ): RTCPeerConnection {
    const existing = this.peers.get(participantId);
    if (existing) return existing;

    const peer = new RTCPeerConnection({
      iceServers: this.options.iceServers
    });

    if (this.localStream) {
      for (const track of this.localStream.getTracks()) {
        peer.addTrack(track, this.localStream);
      }
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
}
