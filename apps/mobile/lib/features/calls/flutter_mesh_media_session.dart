import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef SignalSender = void Function(
  String targetParticipantId,
  Map<String, dynamic> signal,
);

typedef RemoteStreamHandler = void Function(
  String participantId,
  MediaStream stream,
);

typedef PeerStateHandler = void Function(
  String participantId,
  RTCPeerConnectionState state,
);

class PeerQualitySnapshot {
  const PeerQualitySnapshot({
    required this.roundTripTimeMs,
    required this.packetLossPercent,
    required this.jitterMs,
  });

  final double? roundTripTimeMs;
  final double? packetLossPercent;
  final double? jitterMs;

  String get label {
    if ((roundTripTimeMs ?? 0) >= 450 ||
        (packetLossPercent ?? 0) >= 8 ||
        (jitterMs ?? 0) >= 60) {
      return 'Poor';
    }
    if ((roundTripTimeMs ?? 0) >= 220 ||
        (packetLossPercent ?? 0) >= 3 ||
        (jitterMs ?? 0) >= 30) {
      return 'Fair';
    }
    return 'Good';
  }
}

class FlutterMeshMediaSession {
  FlutterMeshMediaSession({
    required this.iceServers,
    required this.sendSignal,
    this.onRemoteStream,
    this.onPeerState,
  });

  final List<Map<String, dynamic>> iceServers;
  final SignalSender sendSignal;
  final RemoteStreamHandler? onRemoteStream;
  final PeerStateHandler? onPeerState;

  MediaStreamTrack? _audioTrack;
  MediaStreamTrack? _cameraTrack;
  MediaStreamTrack? _screenTrack;
  MediaStream? _cameraStream;
  MediaStream? _screenStream;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, MediaStream> _remoteStreams = {};
  bool _deafened = false;

  Future<MediaStream> startAudio({String? deviceId}) async {
    final audioConstraints = deviceId == null
        ? true
        : <String, dynamic>{'deviceId': deviceId};

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': audioConstraints,
      'video': false,
    });

    final tracks = stream.getAudioTracks();
    if (tracks.isEmpty) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      throw StateError('Microphone did not produce an audio track');
    }

    final wasMuted = _audioTrack?.enabled == false;
    _audioTrack?.stop();
    _audioTrack = tracks.first;
    _audioTrack!.enabled = !wasMuted;

    await _replaceTrackForAllPeers(
      kind: 'audio',
      track: _audioTrack!,
      stream: stream,
    );
    return stream;
  }

  Future<MediaStream> startCamera({String? deviceId}) async {
    final videoConstraints = deviceId == null
        ? <String, dynamic>{'facingMode': 'user'}
        : <String, dynamic>{'deviceId': deviceId};

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': videoConstraints,
    });

    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      throw StateError('Camera did not produce a video track');
    }

    final wasDisabled = _cameraTrack?.enabled == false;
    _cameraTrack?.stop();
    _cameraTrack = tracks.first;
    _cameraTrack!.enabled = !wasDisabled;
    _cameraStream = stream;

    if (_screenTrack == null) {
      await _replaceTrackForAllPeers(
        kind: 'video',
        track: _cameraTrack!,
        stream: stream,
      );
    }
    return stream;
  }

  Future<void> connectPeer(
    String participantId, {
    required bool initiator,
  }) async {
    final peer = await _ensurePeer(participantId);
    if (!initiator) return;

    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);

    final sdp = offer.sdp;
    if (sdp != null) {
      sendSignal(participantId, {
        'kind': 'offer',
        'sdp': sdp,
      });
    }
  }

  Future<void> reconnectPeer(
    String participantId, {
    required bool initiator,
  }) async {
    final peer = _peers.remove(participantId);
    if (peer != null) await peer.close();

    final stream = _remoteStreams.remove(participantId);
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
    }

    await connectPeer(participantId, initiator: initiator);
  }

  Future<double?> sampleLocalAudioLevel() async {
    final track = _audioTrack;
    if (track == null || !track.enabled || _peers.isEmpty) return null;

    for (final peer in _peers.values) {
      try {
        final reports = await peer.getStats(track);
        double? level;
        for (final report in reports) {
          final raw = report.values['audioLevel'];
          final value = raw is num
              ? raw.toDouble()
              : double.tryParse(raw?.toString() ?? '');
          if (value != null && (level == null || value > level)) {
            level = value;
          }
        }
        if (level != null) return level;
      } catch (_) {}
    }
    return null;
  }

  Future<PeerQualitySnapshot?> peerQuality(String participantId) async {
    final peer = _peers[participantId];
    if (peer == null) return null;

    try {
      final reports = await peer.getStats();
      double? rttMs;
      double? jitterMs;
      num lost = 0;
      num received = 0;

      for (final report in reports) {
        final values = report.values;
        if (report.type == 'candidate-pair' &&
            values['state']?.toString() == 'succeeded') {
          final rawRtt = values['currentRoundTripTime'];
          final value = rawRtt is num
              ? rawRtt.toDouble()
              : double.tryParse(rawRtt?.toString() ?? '');
          if (value != null) rttMs = value * 1000;
        }

        if (report.type == 'inbound-rtp') {
          final rawLost = values['packetsLost'];
          final rawReceived = values['packetsReceived'];
          final rawJitter = values['jitter'];
          if (rawLost is num) lost += rawLost;
          if (rawReceived is num) received += rawReceived;
          final value = rawJitter is num
              ? rawJitter.toDouble()
              : double.tryParse(rawJitter?.toString() ?? '');
          if (value != null) {
            final ms = value * 1000;
            if (jitterMs == null || ms > jitterMs) jitterMs = ms;
          }
        }
      }

      final total = lost + received;
      final lossPercent =
          total > 0 ? (lost.toDouble() / total.toDouble()) * 100 : null;

      return PeerQualitySnapshot(
        roundTripTimeMs: rttMs,
        packetLossPercent: lossPercent,
        jitterMs: jitterMs,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> handleSignal(
    String fromParticipantId,
    Map<String, dynamic> signal,
  ) async {
    final peer = await _ensurePeer(fromParticipantId);
    final kind = signal['kind'];

    if (kind == 'offer') {
      await peer.setRemoteDescription(
        RTCSessionDescription(signal['sdp'] as String, 'offer'),
      );
      final answer = await peer.createAnswer();
      await peer.setLocalDescription(answer);
      final sdp = answer.sdp;
      if (sdp != null) {
        sendSignal(fromParticipantId, {
          'kind': 'answer',
          'sdp': sdp,
        });
      }
      return;
    }

    if (kind == 'answer') {
      await peer.setRemoteDescription(
        RTCSessionDescription(signal['sdp'] as String, 'answer'),
      );
      return;
    }

    if (kind == 'ice') {
      await peer.addCandidate(
        RTCIceCandidate(
          signal['candidate'] as String?,
          signal['sdpMid'] as String?,
          signal['sdpMLineIndex'] as int?,
        ),
      );
    }
  }

  void setMuted(bool muted) {
    final track = _audioTrack;
    if (track != null) track.enabled = !muted;
  }

  void setDeafened(bool deafened) {
    _deafened = deafened;
    for (final stream in _remoteStreams.values) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !deafened;
      }
    }
  }

  void setCameraEnabled(bool enabled) {
    final track = _cameraTrack;
    if (track != null) track.enabled = enabled;
  }

  Future<List<MediaDeviceInfo>> mediaDevices() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return devices.toList(growable: false);
  }

  Future<void> selectMicrophone(String deviceId) async {
    await startAudio(deviceId: deviceId);
  }

  Future<MediaStream> selectCamera(String deviceId) {
    return startCamera(deviceId: deviceId);
  }

  Future<void> switchCamera() async {
    final track = _cameraTrack;
    if (track == null) {
      throw StateError('Camera is not active');
    }
    await Helper.switchCamera(track);
  }

  Future<MediaStream> startScreenShare() async {
    final stream = await navigator.mediaDevices.getDisplayMedia({
      'video': true,
      'audio': false,
    });

    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      throw StateError('Screen capture did not produce a video track');
    }

    _screenTrack?.stop();
    _screenTrack = tracks.first;
    _screenStream = stream;

    await _replaceTrackForAllPeers(
      kind: 'video',
      track: _screenTrack!,
      stream: stream,
    );
    return stream;
  }

  Future<MediaStream?> stopScreenShare() async {
    _screenTrack?.stop();
    _screenTrack = null;
    _screenStream = null;

    final cameraTrack = _cameraTrack;
    final cameraStream = _cameraStream;
    if (cameraTrack != null && cameraStream != null) {
      await _replaceTrackForAllPeers(
        kind: 'video',
        track: cameraTrack,
        stream: cameraStream,
      );
    }

    return cameraStream;
  }

  Future<void> leave() async {
    for (final peer in _peers.values) {
      await peer.close();
    }
    _peers.clear();

    for (final stream in _remoteStreams.values) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
    }
    _remoteStreams.clear();

    _audioTrack?.stop();
    _cameraTrack?.stop();
    _screenTrack?.stop();
    _audioTrack = null;
    _cameraTrack = null;
    _screenTrack = null;
    _cameraStream = null;
    _screenStream = null;
  }

  Future<RTCPeerConnection> _ensurePeer(
    String participantId,
  ) async {
    final existing = _peers[participantId];
    if (existing != null) return existing;

    final peer = await createPeerConnection({
      'iceServers': iceServers,
    });

    final audioTrack = _audioTrack;
    if (audioTrack != null) {
      final stream = await createLocalMediaStream(
        'pulsemesh-audio-$participantId',
      );
      await stream.addTrack(audioTrack);
      await peer.addTrack(audioTrack, stream);
    }

    final videoTrack = _screenTrack ?? _cameraTrack;
    final videoStream = _screenStream ?? _cameraStream;
    if (videoTrack != null && videoStream != null) {
      await peer.addTrack(videoTrack, videoStream);
    }

    peer.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null) return;
      sendSignal(participantId, {
        'kind': 'ice',
        'candidate': value,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    peer.onConnectionState = (state) {
      onPeerState?.call(participantId, state);
    };

    peer.onTrack = (event) {
      if (event.streams.isEmpty) return;
      final stream = event.streams.first;
      _remoteStreams[participantId] = stream;
      for (final track in stream.getAudioTracks()) {
        track.enabled = !_deafened;
      }
      onRemoteStream?.call(participantId, stream);
    };

    _peers[participantId] = peer;
    return peer;
  }

  Future<void> _replaceTrackForAllPeers({
    required String kind,
    required MediaStreamTrack track,
    required MediaStream stream,
  }) async {
    for (final peer in _peers.values) {
      final senders = await peer.getSenders();
      final matching = senders
          .where((sender) => sender.track?.kind == kind)
          .toList();
      if (matching.isNotEmpty) {
        await matching.first.replaceTrack(track);
      } else {
        await peer.addTrack(track, stream);
      }
    }
  }
}
