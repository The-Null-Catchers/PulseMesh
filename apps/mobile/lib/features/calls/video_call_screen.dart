import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../offline/models.dart';
import '../inbox/inbox_realtime.dart';
import '../inbox/mobile_data_controller.dart';
import '../inbox/mobile_data_scope.dart';
import 'call_transport.dart';
import 'flutter_mesh_media_session.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    required this.conversationId,
    required this.title,
    super.key,
  });

  final String conversationId;
  final String title;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  MobileDataController? _data;
  StreamSubscription<Map<String, dynamic>>? _events;
  FlutterMeshMediaSession? _media;
  ActiveCall? _call;
  String? _selfParticipantId;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  late final Future<void> _rendererInitialization;
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Set<String> _speakingParticipants = <String>{};
  final Map<String, RTCPeerConnectionState> _peerStates =
      <String, RTCPeerConnectionState>{};
  final Map<String, PeerQualitySnapshot> _peerQuality =
      <String, PeerQualitySnapshot>{};
  final Map<String, DateTime> _speakingExpiresAt = <String, DateTime>{};
  final Set<String> _recoveringPeers = <String>{};

  bool _rendererReady = false;
  bool _loading = true;
  bool _leaving = false;
  bool _muted = false;
  bool _deafened = false;
  bool _cameraEnabled = true;
  bool _speaker = true;
  bool _switchingCamera = false;
  bool _screenSharing = false;
  bool _screenShareBusy = false;
  Object? _error;
  Timer? _telemetryTimer;
  Timer? _speakingExpiryTimer;
  bool _localSpeaking = false;
  MobileRealtimeState? _lastRealtimeState;

  RoomRef get _room =>
      RoomRef(kind: RoomKind.conversation, id: widget.conversationId);

  @override
  void initState() {
    super.initState();
    _rendererInitialization = _initializeRenderer();
  }

  Future<void> _initializeRenderer() async {
    await _localRenderer.initialize();
    if (!mounted) return;
    setState(() => _rendererReady = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MobileDataScope.of(context);
    if (identical(_data, next)) return;

    _data?.removeListener(_onDataChanged);
    _events?.cancel();
    _data = next;
    _lastRealtimeState = next.realtimeState;
    next.addListener(_onDataChanged);
    _events = next.realtimeEvents.listen(_handleRealtimeEvent);
    next.watchCallRoom(_room);
    unawaited(_join());
  }

  Future<void> _join() async {
    final data = _data;
    if (data == null) return;
    if (!_rendererReady) {
      await _rendererInitialization;
      if (!mounted) return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    String? startedCallId;
    try {
      final results = await Future.wait<Object>([
        data.callIceServers(),
        data.startConversationCall(
          widget.conversationId,
          kind: 'video',
        ),
      ]);
      final iceServers = results[0] as List<Map<String, dynamic>>;
      final call = results[1] as ActiveCall;
      startedCallId = call.id;
      if (call.kind != 'video') {
        throw StateError(
          'A voice call is already active in this conversation.',
        );
      }

      CallParticipant? self;
      for (final participant in call.participants) {
        if (participant.userId == data.currentUserId) {
          self = participant;
          break;
        }
      }
      if (self == null) {
        throw StateError('Current call participant could not be resolved');
      }

      final media = FlutterMeshMediaSession(
        iceServers: iceServers,
        sendSignal: (targetParticipantId, signal) {
          data.sendCallSignal(
            callId: call.id,
            targetParticipantId: targetParticipantId,
            signal: signal,
          );
        },
        onRemoteStream: (participantId, stream) {
          unawaited(_attachRemoteStream(participantId, stream));
        },
        onPeerState: _onPeerState,
      );

      _media = media;
      _call = call;
      _selfParticipantId = self.id;
      _muted = self.muted;
      _deafened = self.deafened;
      _cameraEnabled = true;

      await media.startAudio();
      media.setMuted(_muted);
      media.setDeafened(_deafened);

      final localStream = await media.startCamera();
      _localRenderer.srcObject = localStream;

      await data.updateCallParticipant(
        call.id,
        cameraEnabled: true,
        screenSharing: false,
        connectionState: 'connected',
      );

      for (final participant in call.participants) {
        if (participant.id == self.id) continue;
        await media.connectPeer(
          participant.id,
          initiator: self.id.compareTo(participant.id) < 0,
        );
      }

      _startTelemetry();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (startedCallId != null) {
        unawaited(data.leaveCall(startedCallId));
      }
      await _media?.leave();
      _media = null;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _attachRemoteStream(
    String participantId,
    MediaStream stream,
  ) async {
    var renderer = _remoteRenderers[participantId];
    if (renderer == null) {
      renderer = RTCVideoRenderer();
      await renderer.initialize();
      _remoteRenderers[participantId] = renderer;
    }
    renderer.srcObject = stream;
    if (mounted) setState(() {});
  }

  void _onDataChanged() {
    final data = _data;
    final call = _call;
    if (data == null || call == null) return;

    final previous = _lastRealtimeState;
    final current = data.realtimeState;
    _lastRealtimeState = current;
    if (previous == current) return;

    if (current == MobileRealtimeState.ready &&
        previous != MobileRealtimeState.ready) {
      unawaited(_recoverAfterReconnect());
    }
  }

  Future<void> _recoverAfterReconnect() async {
    final data = _data;
    final call = _call;
    final media = _media;
    final selfId = _selfParticipantId;
    if (data == null || call == null || media == null || selfId == null) return;

    try {
      final refreshed = await data.refreshCall(call.id);
      if (!mounted) return;
      setState(() => _call = refreshed);

      for (final participant in refreshed.participants) {
        if (participant.id == selfId) continue;
        await media.connectPeer(
          participant.id,
          initiator: selfId.compareTo(participant.id) < 0,
        );
      }

      await data.updateCallParticipant(
        call.id,
        cameraEnabled: _cameraEnabled,
        screenSharing: _screenSharing,
        connectionState: 'connected',
      );
    } catch (_) {}
  }

  void _handleRealtimeEvent(Map<String, dynamic> event) {
    final call = _call;
    if (call == null) return;

    final type = event['type'] as String?;
    final payloadValue = event['payload'];
    if (payloadValue is! Map) return;
    final payload = Map<String, dynamic>.from(payloadValue);

    if (payload['callId'] != call.id) return;

    if (type == 'call.speaking') {
      final participantId = payload['participantId'] as String?;
      if (participantId == null) return;
      final speaking = payload['speaking'] as bool? ?? false;
      if (speaking) {
        _speakingParticipants.add(participantId);
        final rawExpiry = payload['expiresAt'] as String?;
        _speakingExpiresAt[participantId] = rawExpiry == null
            ? DateTime.now().toUtc().add(const Duration(seconds: 3))
            : DateTime.parse(rawExpiry).toUtc();
        _ensureSpeakingSweep();
      } else {
        _speakingParticipants.remove(participantId);
        _speakingExpiresAt.remove(participantId);
      }
      if (mounted) setState(() {});
      return;
    }

    if (type == 'call.signal') {
      final fromParticipantId = payload['fromParticipantId'] as String?;
      final signalValue = payload['signal'];
      if (fromParticipantId == null || signalValue is! Map) return;

      final future = _media?.handleSignal(
        fromParticipantId,
        Map<String, dynamic>.from(signalValue),
      );
      if (future != null) unawaited(future.catchError((_) {}));
      return;
    }

    if (type == 'call.ended') {
      unawaited(_handleRemoteEnd());
      return;
    }

    if (type == 'call.participant.joined' ||
        type == 'call.participant.left' ||
        type == 'call.participant.updated') {
      unawaited(
        _refreshParticipants(connectNew: type == 'call.participant.joined'),
      );
    }
  }

  Future<void> _refreshParticipants({required bool connectNew}) async {
    final data = _data;
    final call = _call;
    final media = _media;
    final selfId = _selfParticipantId;
    if (data == null || call == null) return;

    try {
      final refreshed = await data.refreshCall(call.id);
      final activeIds = refreshed.participants.map((item) => item.id).toSet();

      final removedIds = _remoteRenderers.keys
          .where((id) => !activeIds.contains(id))
          .toList(growable: false);
      for (final id in removedIds) {
        final renderer = _remoteRenderers.remove(id);
        renderer?.srcObject = null;
        await renderer?.dispose();
      }

      if (!mounted) return;
      setState(() => _call = refreshed);

      if (connectNew && media != null && selfId != null) {
        for (final participant in refreshed.participants) {
          if (participant.id == selfId) continue;
          await media.connectPeer(
            participant.id,
            initiator: selfId.compareTo(participant.id) < 0,
          );
        }
      }
    } catch (_) {}
  }

  void _onPeerState(
    String participantId,
    RTCPeerConnectionState state,
  ) {
    if (!mounted) return;
    setState(() => _peerStates[participantId] = state);

    if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
      unawaited(_recoverPeer(participantId));
    }
  }

  Future<void> _recoverPeer(String participantId) async {
    if (_recoveringPeers.contains(participantId)) return;
    final media = _media;
    final selfId = _selfParticipantId;
    if (media == null || selfId == null) return;

    _recoveringPeers.add(participantId);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final state = _peerStates[participantId];
      if (state != RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          state != RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        return;
      }
      await media.reconnectPeer(
        participantId,
        initiator: selfId.compareTo(participantId) < 0,
      );
    } catch (_) {
    } finally {
      _recoveringPeers.remove(participantId);
    }
  }

  void _startTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_tickTelemetry()),
    );
  }

  Future<void> _tickTelemetry() async {
    final media = _media;
    final call = _call;
    final data = _data;
    final selfId = _selfParticipantId;
    if (media == null || call == null || data == null || selfId == null) return;

    final level = await media.sampleLocalAudioLevel();
    final speaking = !_muted && level != null && level >= 0.025;
    if (speaking != _localSpeaking) {
      _localSpeaking = speaking;
      data.sendCallSpeaking(callId: call.id, speaking: speaking);
    }

    final nextQuality = <String, PeerQualitySnapshot>{};
    for (final participant in call.participants) {
      if (participant.id == selfId) continue;
      final quality = await media.peerQuality(participant.id);
      if (quality != null) nextQuality[participant.id] = quality;
    }
    if (!mounted) return;
    setState(() {
      _peerQuality
        ..clear()
        ..addAll(nextQuality);
    });
  }

  void _ensureSpeakingSweep() {
    if (_speakingExpiryTimer?.isActive == true) return;
    _speakingExpiryTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = DateTime.now().toUtc();
      final expired = _speakingExpiresAt.entries
          .where((entry) => !entry.value.isAfter(now))
          .map((entry) => entry.key)
          .toList(growable: false);
      if (expired.isEmpty) return;
      for (final id in expired) {
        _speakingExpiresAt.remove(id);
        _speakingParticipants.remove(id);
      }
      if (mounted) setState(() {});
      if (_speakingExpiresAt.isEmpty) {
        _speakingExpiryTimer?.cancel();
        _speakingExpiryTimer = null;
      }
    });
  }

  Future<void> _toggleMute() async {
    final data = _data;
    final call = _call;
    final media = _media;
    if (data == null || call == null || media == null) return;

    final next = !_muted;
    media.setMuted(next);
    if (next && _localSpeaking) {
      _localSpeaking = false;
      data.sendCallSpeaking(callId: call.id, speaking: false);
    }
    setState(() => _muted = next);

    try {
      await data.updateCallParticipant(call.id, muted: next);
    } catch (_) {
      media.setMuted(!next);
      if (mounted) setState(() => _muted = !next);
    }
  }

  Future<void> _toggleDeafen() async {
    final data = _data;
    final call = _call;
    final media = _media;
    if (data == null || call == null || media == null) return;

    final next = !_deafened;
    media.setDeafened(next);
    setState(() => _deafened = next);

    try {
      await data.updateCallParticipant(call.id, deafened: next);
    } catch (_) {
      media.setDeafened(!next);
      if (mounted) setState(() => _deafened = !next);
    }
  }

  Future<void> _toggleCamera() async {
    final data = _data;
    final call = _call;
    final media = _media;
    if (data == null || call == null || media == null) return;

    final next = !_cameraEnabled;
    media.setCameraEnabled(next);
    setState(() => _cameraEnabled = next);

    try {
      await data.updateCallParticipant(call.id, cameraEnabled: next);
    } catch (_) {
      media.setCameraEnabled(!next);
      if (mounted) setState(() => _cameraEnabled = !next);
    }
  }

  Future<void> _toggleScreenShare() async {
    final data = _data;
    final call = _call;
    final media = _media;
    if (data == null ||
        call == null ||
        media == null ||
        _screenShareBusy) {
      return;
    }

    setState(() => _screenShareBusy = true);
    try {
      if (_screenSharing) {
        final cameraStream = await media.stopScreenShare();
        _localRenderer.srcObject = cameraStream;
        await data.updateCallParticipant(
          call.id,
          screenSharing: false,
        );
        if (mounted) {
          setState(() => _screenSharing = false);
        }
      } else {
        final screenStream = await media.startScreenShare();
        _localRenderer.srcObject = screenStream;
        await data.updateCallParticipant(
          call.id,
          screenSharing: true,
        );
        if (mounted) {
          setState(() => _screenSharing = true);
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Screen sharing is not available or permission was denied.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _screenShareBusy = false);
    }
  }

  Future<void> _switchCamera() async {
    final media = _media;
    if (media == null || !_cameraEnabled || _switchingCamera) return;

    setState(() => _switchingCamera = true);
    try {
      await media.switchCamera();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not switch camera.')),
      );
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _showMediaDevices() async {
    final media = _media;
    if (media == null) return;

    try {
      final devices = await media.mediaDevices();
      final microphones = devices
          .where((device) => device.kind == 'audioinput')
          .toList(growable: false);
      final cameras = devices
          .where((device) => device.kind == 'videoinput')
          .toList(growable: false);

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF071015),
        builder: (sheetContext) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text(
                    'Call devices',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const ListTile(
                  dense: true,
                  leading: Icon(Icons.mic_outlined),
                  title: Text('Microphones'),
                ),
                if (microphones.isEmpty)
                  const ListTile(title: Text('No microphones found.')),
                for (var index = 0; index < microphones.length; index += 1)
                  ListTile(
                    title: Text(
                      microphones[index].label.isEmpty
                          ? 'Microphone ${index + 1}'
                          : microphones[index].label,
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _selectMicrophone(microphones[index]);
                    },
                  ),
                const Divider(),
                const ListTile(
                  dense: true,
                  leading: Icon(Icons.videocam_outlined),
                  title: Text('Cameras'),
                ),
                if (cameras.isEmpty)
                  const ListTile(title: Text('No cameras found.')),
                for (var index = 0; index < cameras.length; index += 1)
                  ListTile(
                    title: Text(
                      cameras[index].label.isEmpty
                          ? 'Camera ${index + 1}'
                          : cameras[index].label,
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _selectCamera(cameras[index]);
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load call devices.')),
      );
    }
  }

  Future<void> _selectMicrophone(MediaDeviceInfo device) async {
    final media = _media;
    if (media == null) return;

    try {
      await media.selectMicrophone(device.deviceId);
      media.setMuted(_muted);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            device.label.isEmpty
                ? 'Microphone changed.'
                : 'Using ${device.label}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not switch microphone.')),
      );
    }
  }

  Future<void> _selectCamera(MediaDeviceInfo device) async {
    final media = _media;
    if (media == null) return;

    try {
      final stream = await media.selectCamera(device.deviceId);
      if (!_screenSharing) {
        _localRenderer.srcObject = stream;
      }
      media.setCameraEnabled(_cameraEnabled);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            device.label.isEmpty ? 'Camera changed.' : 'Using ${device.label}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not switch camera.')),
      );
    }
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speaker;
    try {
      await Helper.setSpeakerphoneOn(next);
      if (mounted) setState(() => _speaker = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not change audio output.')),
      );
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);

    final data = _data;
    final call = _call;
    try {
      if (call != null) {
        await data?.leaveCall(call.id);
      }
    } finally {
      await _shutdownMedia();
      data?.unwatchCallRoom(_room);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _shutdownMedia() async {
    _telemetryTimer?.cancel();
    _speakingExpiryTimer?.cancel();
    final data = _data;
    final call = _call;
    if (_localSpeaking && data != null && call != null) {
      data.sendCallSpeaking(callId: call.id, speaking: false);
    }
    _localSpeaking = false;
    await _media?.leave();
    _media = null;
    _localRenderer.srcObject = null;

    for (final renderer in _remoteRenderers.values) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
    _remoteRenderers.clear();
    _call = null;
  }

  Future<void> _handleRemoteEnd() async {
    await _shutdownMedia();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Video call ended.')),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _events?.cancel();
    _telemetryTimer?.cancel();
    _speakingExpiryTimer?.cancel();
    final data = _data;
    data?.removeListener(_onDataChanged);
    data?.unwatchCallRoom(_room);

    if (!_leaving) {
      final call = _call;
      if (call != null) unawaited(data?.leaveCall(call.id));
      unawaited(_media?.leave());
    }

    for (final renderer in _remoteRenderers.values) {
      unawaited(renderer.dispose());
    }
    _remoteRenderers.clear();
    unawaited(_localRenderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;

    return Scaffold(
      backgroundColor: const Color(0xFF03090C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF071015),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              _data == null
                  ? 'Connecting…'
                  : _connectionLabel(_data!.realtimeState),
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _VideoError(onRetry: _join)
                : call == null
                    ? const Center(child: Text('Video call is no longer active.'))
                    : Column(
                        children: [
                          Expanded(child: _buildVideoGrid(call)),
                          _VideoControls(
                            muted: _muted,
                            deafened: _deafened,
                            cameraEnabled: _cameraEnabled,
                            screenSharing: _screenSharing,
                            screenShareBusy: _screenShareBusy,
                            speaker: _speaker,
                            switchingCamera: _switchingCamera,
                            leaving: _leaving,
                            onMute: _toggleMute,
                            onDeafen: _toggleDeafen,
                            onCamera: _toggleCamera,
                            onDevices: _showMediaDevices,
                            onScreenShare: _toggleScreenShare,
                            onSwitchCamera: _switchCamera,
                            onSpeaker: _toggleSpeaker,
                            onLeave: _leave,
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildVideoGrid(ActiveCall call) {
    final participants = call.participants;
    final columns = participants.length <= 2 ? 1 : 2;

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: participants.length <= 2 ? 16 / 10 : 1,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final participant = participants[index];
        final isSelf = participant.id == _selfParticipantId;
        final renderer =
            isSelf ? _localRenderer : _remoteRenderers[participant.id];
        final showVideo = isSelf
            ? (_cameraEnabled || _screenSharing) &&
                _localRenderer.srcObject != null
            : (participant.cameraEnabled || participant.screenSharing) &&
                renderer != null &&
                renderer.srcObject != null;

        return _VideoParticipantTile(
          participant: participant,
          renderer: renderer,
          showVideo: showVideo,
          isSelf: isSelf,
          speaking: _speakingParticipants.contains(participant.id),
          peerState: _peerStates[participant.id],
          quality: _peerQuality[participant.id],
          screenSharing: isSelf ? _screenSharing : participant.screenSharing,
        );
      },
    );
  }
}

class _VideoParticipantTile extends StatelessWidget {
  const _VideoParticipantTile({
    required this.participant,
    required this.renderer,
    required this.showVideo,
    required this.isSelf,
    required this.speaking,
    required this.peerState,
    required this.quality,
    required this.screenSharing,
  });

  final CallParticipant participant;
  final RTCVideoRenderer? renderer;
  final bool showVideo;
  final bool isSelf;
  final bool speaking;
  final RTCPeerConnectionState? peerState;
  final PeerQualitySnapshot? quality;
  final bool screenSharing;

  @override
  Widget build(BuildContext context) {
    final label = participant.displayName.trim().isNotEmpty
        ? participant.displayName
        : participant.username.trim().isNotEmpty
            ? '@${participant.username}'
            : 'Member';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: speaking ? const Color(0xFF68E0CF) : const Color(0xFF173039),
          width: speaking ? 2.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: const Color(0xFF0D1A20),
            child: showVideo && renderer != null
                ? RTCVideoView(
                    renderer!,
                    mirror: isSelf,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Center(
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: const Color(0xFF173039),
                      child: Text(
                        label.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 9,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isSelf ? '$label (You)' : label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(blurRadius: 6, color: Colors.black),
                      ],
                    ),
                  ),
                ),
                if (participant.muted)
                  const Icon(
                    Icons.mic_off_rounded,
                    size: 16,
                    color: Colors.redAccent,
                  ),
              ],
            ),
          ),
          Positioned(
            left: 10,
            top: 9,
            child: _QualityBadge(
              speaking: speaking,
              isSelf: isSelf,
              peerState: peerState,
              quality: quality,
              screenSharing: screenSharing,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({
    required this.speaking,
    required this.isSelf,
    required this.peerState,
    required this.quality,
    required this.screenSharing,
  });

  final bool speaking;
  final bool isSelf;
  final RTCPeerConnectionState? peerState;
  final PeerQualitySnapshot? quality;
  final bool screenSharing;

  @override
  Widget build(BuildContext context) {
    final label = speaking
        ? 'Speaking'
        : screenSharing
            ? 'Sharing screen'
            : !isSelf &&
                peerState == RTCPeerConnectionState.RTCPeerConnectionStateFailed
            ? 'Retrying'
            : !isSelf &&
                    peerState ==
                        RTCPeerConnectionState
                            .RTCPeerConnectionStateDisconnected
                ? 'Reconnecting'
                : !isSelf && quality != null
                    ? quality!.label
                    : isSelf
                        ? 'You'
                        : 'Connecting';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x9903090C),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 9, color: Colors.white70),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({
    required this.muted,
    required this.deafened,
    required this.cameraEnabled,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.speaker,
    required this.switchingCamera,
    required this.leaving,
    required this.onMute,
    required this.onDeafen,
    required this.onCamera,
    required this.onDevices,
    required this.onScreenShare,
    required this.onSwitchCamera,
    required this.onSpeaker,
    required this.onLeave,
  });

  final bool muted;
  final bool deafened;
  final bool cameraEnabled;
  final bool screenSharing;
  final bool screenShareBusy;
  final bool speaker;
  final bool switchingCamera;
  final bool leaving;
  final Future<void> Function() onMute;
  final Future<void> Function() onDeafen;
  final Future<void> Function() onCamera;
  final Future<void> Function() onDevices;
  final Future<void> Function() onScreenShare;
  final Future<void> Function() onSwitchCamera;
  final Future<void> Function() onSpeaker;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF071015),
        border: Border(top: BorderSide(color: Color(0xFF173039))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Control(
              icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: muted ? 'Unmute' : 'Mute',
              active: muted,
              onPressed: onMute,
            ),
            _Control(
              icon: cameraEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              label: cameraEnabled ? 'Camera' : 'Camera off',
              active: !cameraEnabled,
              onPressed: onCamera,
            ),
            _Control(
              icon: switchingCamera
                  ? Icons.sync_rounded
                  : Icons.cameraswitch_rounded,
              label: 'Flip',
              onPressed:
                  cameraEnabled && !switchingCamera ? onSwitchCamera : null,
            ),
            _Control(
              icon: screenShareBusy
                  ? Icons.sync_rounded
                  : screenSharing
                      ? Icons.stop_screen_share_outlined
                      : Icons.screen_share_outlined,
              label: screenSharing ? 'Stop share' : 'Share',
              active: screenSharing,
              onPressed: screenShareBusy ? null : onScreenShare,
            ),
            _Control(
              icon: Icons.tune_rounded,
              label: 'Devices',
              onPressed: onDevices,
            ),
            _Control(
              icon: speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
              label: 'Speaker',
              active: speaker,
              onPressed: onSpeaker,
            ),
            _Control(
              icon: deafened
                  ? Icons.headset_off_rounded
                  : Icons.headphones_rounded,
              label: deafened ? 'Undeafen' : 'Deafen',
              active: deafened,
              onPressed: onDeafen,
            ),
            _Control(
              icon: Icons.call_end_rounded,
              label: 'Leave',
              danger: true,
              onPressed: leaving ? null : onLeave,
            ),
          ],
        ),
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final Future<void> Function()? onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? Colors.redAccent
        : active
            ? const Color(0xFF68E0CF)
            : const Color(0xFF13242B);
    final foreground = danger || active ? Colors.black : Colors.white;

    return SizedBox(
      width: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            onPressed:
                onPressed == null ? null : () => unawaited(onPressed!()),
            style: IconButton.styleFrom(
              backgroundColor: background,
              foregroundColor: foreground,
            ),
            icon: Icon(icon),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _VideoError extends StatelessWidget {
  const _VideoError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              size: 44,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not start this video call.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _connectionLabel(MobileRealtimeState state) {
  return switch (state) {
    MobileRealtimeState.ready => 'Realtime connected',
    MobileRealtimeState.connecting => 'Connecting…',
    MobileRealtimeState.reconnecting => 'Reconnecting…',
    MobileRealtimeState.disconnected => 'Disconnected',
  };
}
