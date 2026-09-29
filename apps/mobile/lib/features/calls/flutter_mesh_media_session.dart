import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef SignalSender = void Function(
  String targetParticipantId,
  Map<String, dynamic> signal,
);

typedef RemoteStreamHandler = void Function(
  String participantId,
  MediaStream stream,
);

class FlutterMeshMediaSession {
  FlutterMeshMediaSession({
    required this.iceServers,
    required this.sendSignal,
    this.onRemoteStream,
  });

  final List<Map<String, dynamic>> iceServers;
  final SignalSender sendSignal;
  final RemoteStreamHandler? onRemoteStream;

  MediaStream? _localStream;
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

    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localStream = stream;

    final tracks = stream.getAudioTracks();
    if (tracks.isNotEmpty) {
      final track = tracks.first;
      for (final peer in _peers.values) {
        final senders = await peer.getSenders();
        final audioSenders = senders
            .where((sender) => sender.track?.kind == 'audio')
            .toList();
        if (audioSenders.isNotEmpty) {
          await audioSenders.first.replaceTrack(track);
        } else {
          await peer.addTrack(track, stream);
        }
      }
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
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  void setDeafened(bool deafened) {
    _deafened = deafened;
    for (final stream in _remoteStreams.values) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !deafened;
      }
    }
  }

  Future<void> selectMicrophone(String deviceId) async {
    final currentTracks = _localStream?.getAudioTracks() ?? [];
    final wasMuted =
        currentTracks.isNotEmpty && !currentTracks.first.enabled;
    final stream = await startAudio(deviceId: deviceId);
    if (wasMuted) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = false;
      }
    }
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

    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localStream = null;
  }

  Future<RTCPeerConnection> _ensurePeer(
    String participantId,
  ) async {
    final existing = _peers[participantId];
    if (existing != null) return existing;

    final peer = await createPeerConnection({
      'iceServers': iceServers,
    });

    final localStream = _localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        await peer.addTrack(track, localStream);
      }
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
}
