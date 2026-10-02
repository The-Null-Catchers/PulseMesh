
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../offline/models.dart';
import '../inbox/inbox_realtime.dart';
import '../inbox/mobile_data_controller.dart';
import '../inbox/mobile_data_scope.dart';
import 'call_transport.dart';
import 'flutter_mesh_media_session.dart';

class VoiceRoomScreen extends StatefulWidget {
  const VoiceRoomScreen({
    required this.channelId,
    required this.title,
    super.key,
  });

  final String channelId;
  final String title;

  @override
  State<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends State<VoiceRoomScreen> {
  MobileDataController? _data;
  StreamSubscription<Map<String, dynamic>>? _events;
  FlutterMeshMediaSession? _media;
  ActiveCall? _call;
  String? _selfParticipantId;
  bool _loading = true;
  bool _leaving = false;
  bool _muted = false;
  bool _deafened = false;
  bool _speaker = false;
  Object? _error;
  MobileRealtimeState? _lastRealtimeState;
  final Set<String> _remoteStreamParticipants = <String>{};
  final Set<String> _speakingParticipants = <String>{};
  final Map<String, DateTime> _speakingExpiresAt = <String, DateTime>{};
  final Map<String, RTCPeerConnectionState> _peerStates =
      <String, RTCPeerConnectionState>{};
  final Map<String, PeerQualitySnapshot> _peerQuality =
      <String, PeerQualitySnapshot>{};
  final Set<String> _recoveringPeers = <String>{};
  Timer? _speakingMonitorTimer;
  Timer? _speakingExpiryTimer;
  Timer? _qualityTimer;
  bool _localSpeaking = false;
  final Set<String> _speakingParticipants = <String>{};
  final Map<String, String> _peerStates = <String, String>{};
  final Map<String, Timer> _speakingTimers = <String, Timer>{};
  final Set<String> _recoveringPeers = <String>{};

  RoomRef get _room =>
      RoomRef(kind: RoomKind.channel, id: widget.channelId);

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

    setState(() {
      _loading = true;
      _error = null;
    });

    String? startedCallId;
    try {
      final results = await Future.wait<Object>([
        data.callIceServers(),
        data.startVoiceCall(widget.channelId),
      ]);
      final iceServers = results[0] as List<Map<String, dynamic>>;
      final call = results[1] as ActiveCall;
      startedCallId = call.id;

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
          if (!mounted) return;
          setState(() => _remoteStreamParticipants.add(participantId));
        },
        onPeerState: _handlePeerState,
        onPeerState: (participantId, state) {
          if (!mounted) return;
          final label = state.toString().split('.').last;
          setState(() => _peerStates[participantId] = label);
          if (label.toLowerCase().contains('failed') ||
              label.toLowerCase().contains('disconnected')) {
            unawaited(_recoverPeer(participantId));
          }
        },
      );

      _media = media;
      _call = call;
      _selfParticipantId = self.id;
      _muted = self.muted;
      _deafened = self.deafened;

      await media.startAudio();
      media.setMuted(_muted);
      media.setDeafened(_deafened);

      for (final participant in call.participants) {
        if (participant.id == self.id) continue;
        await media.connectPeer(
          participant.id,
          initiator: self.id.compareTo(participant.id) < 0,
        );
      }

      await data.updateCallParticipant(
        call.id,
        connectionState: 'connected',
      );
      _startTelemetry();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (startedCallId != null) {
        unawaited(data.leaveCall(startedCallId));
      }
      _speakingMonitorTimer?.cancel();
      _qualityTimer?.cancel();
      _speakingExpiryTimer?.cancel();
      if (_localSpeaking && call != null) {
        data?.sendCallSpeaking(callId: call.id, speaking: false);
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

  void _onDataChanged() {
    final data = _data;
    final call = _call;
    if (data == null || call == null) return;

    final previous = _lastRealtimeState;
    final current = data.realtimeState;
    _lastRealtimeState = current;
    if (previous == current) return;

    if (current == MobileRealtimeState.reconnecting ||
        current == MobileRealtimeState.disconnected) {
      unawaited(
        data.updateCallParticipant(
          call.id,
          connectionState: 'reconnecting',
        ).catchError((_) => _fallbackParticipant()),
      );
      if (mounted) setState(() {});
      return;
    }

    if (current == MobileRealtimeState.ready &&
        previous != MobileRealtimeState.ready) {
      unawaited(_recoverAfterReconnect());
    }
  }

  CallParticipant _fallbackParticipant() {
    final call = _call;
    if (call == null || call.participants.isEmpty) {
      throw StateError('No active participant');
    }
    return call.participants.first;
  }

  Future<void> _recoverAfterReconnect() async {
    final data = _data;
    final call = _call;
    final media = _media;
    final selfId = _selfParticipantId;
    if (data == null || call == null || media == null || selfId == null) return;

    try {
      final refreshed = await data.refreshCall(call.id);
      final activeIds = refreshed.participants.map((item) => item.id).toSet();
      final removed = _peerStates.keys
          .where((id) => !activeIds.contains(id))
          .toList(growable: false);
      for (final id in removed) {
        _peerStates.remove(id);
        _remoteStreamParticipants.remove(id);
        _speakingParticipants.remove(id);
        _speakingTimers.remove(id)?.cancel();
        await media?.removePeer(id);
      }
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
        connectionState: 'connected',
      );
    } catch (_) {}
  }

  Future<void> _recoverPeer(String participantId) async {
    final media = _media;
    final selfId = _selfParticipantId;
    if (media == null ||
        selfId == null ||
        _recoveringPeers.contains(participantId)) {
      return;
    }

    _recoveringPeers.add(participantId);
    try {
      await media.reconnectPeer(
        participantId,
        initiator: selfId.compareTo(participantId) < 0,
      );
    } catch (_) {
      // Realtime/session recovery can retry this peer later.
    } finally {
      _recoveringPeers.remove(participantId);
    }
  }

  void _setSpeaking(String participantId, bool speaking, String? expiresAt) {
    _speakingTimers.remove(participantId)?.cancel();

    if (!speaking) {
      if (mounted) {
        setState(() => _speakingParticipants.remove(participantId));
      }
      return;
    }

    if (mounted) {
      setState(() => _speakingParticipants.add(participantId));
    }

    final expiry = expiresAt == null
        ? DateTime.now().toUtc().add(const Duration(seconds: 3))
        : DateTime.tryParse(expiresAt)?.toUtc() ??
            DateTime.now().toUtc().add(const Duration(seconds: 3));
    final delay = expiry.difference(DateTime.now().toUtc());
    _speakingTimers[participantId] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        _speakingTimers.remove(participantId);
        if (mounted) {
          setState(() => _speakingParticipants.remove(participantId));
        }
      },
    );
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
      if (participantId != null) {
        _setSpeaking(
          participantId,
          payload['speaking'] as bool? ?? false,
          payload['expiresAt'] as String?,
        );
      }
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

    if (type == 'call.speaking') {
      final participantId = payload['participantId'] as String?;
      final speaking = payload['speaking'] as bool? ?? false;
      if (participantId == null) return;

      if (speaking) {
        final expiresAt = payload['expiresAt'] as String?;
        _speakingExpiresAt[participantId] = expiresAt == null
            ? DateTime.now().toUtc().add(const Duration(seconds: 3))
            : DateTime.parse(expiresAt).toUtc();
        _speakingParticipants.add(participantId);
        _startSpeakingExpirySweep();
      } else {
        _speakingExpiresAt.remove(participantId);
        _speakingParticipants.remove(participantId);
      }
      if (mounted) setState(() {});
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

  void _handlePeerState(
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
      // A later state transition or realtime reconnect will retry.
    } finally {
      _recoveringPeers.remove(participantId);
    }
  }

  void _startTelemetry() {
    _speakingMonitorTimer?.cancel();
    _qualityTimer?.cancel();

    _speakingMonitorTimer = Timer.periodic(
      const Duration(milliseconds: 450),
      (_) => unawaited(_sampleLocalSpeaking()),
    );

    _qualityTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshPeerQuality()),
    );
  }

  Future<void> _sampleLocalSpeaking() async {
    final media = _media;
    final call = _call;
    final data = _data;
    if (media == null || call == null || data == null) return;

    final level = await media.sampleLocalAudioLevel();
    final speaking = !_muted && level != null && level >= 0.025;
    if (speaking == _localSpeaking) return;

    _localSpeaking = speaking;
    data.sendCallSpeaking(callId: call.id, speaking: speaking);
  }

  void _startSpeakingExpirySweep() {
    if (_speakingExpiryTimer?.isActive == true) return;

    _speakingExpiryTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = DateTime.now().toUtc();
      final expired = _speakingExpiresAt.entries
          .where((entry) => !entry.value.isAfter(now))
          .map((entry) => entry.key)
          .toList(growable: false);
      if (expired.isEmpty) return;

      for (final participantId in expired) {
        _speakingExpiresAt.remove(participantId);
        _speakingParticipants.remove(participantId);
      }
      if (mounted) setState(() {});

      if (_speakingExpiresAt.isEmpty) {
        _speakingExpiryTimer?.cancel();
        _speakingExpiryTimer = null;
      }
    });
  }

  Future<void> _refreshPeerQuality() async {
    final media = _media;
    final call = _call;
    final selfId = _selfParticipantId;
    if (media == null || call == null || selfId == null) return;

    final next = <String, PeerQualitySnapshot>{};
    for (final participant in call.participants) {
      if (participant.id == selfId) continue;
      final snapshot = await media.peerQuality(participant.id);
      if (snapshot != null) next[participant.id] = snapshot;
    }

    if (!mounted) return;
    setState(() {
      _peerQuality
        ..clear()
        ..addAll(next);
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
    _leaving = true;

    final data = _data;
    final call = _call;
    try {
      if (call != null) {
        await data?.leaveCall(call.id);
      }
    } finally {
      await _media?.leave();
      _media = null;
      _call = null;
      data?.unwatchCallRoom(_room);

      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleRemoteEnd() async {
    await _media?.leave();
    _media = null;
    if (!mounted) return;
    setState(() => _call = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice room ended.')),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final timer in _speakingTimers.values) {
      timer.cancel();
    }
    _speakingTimers.clear();
    _events?.cancel();
    _speakingMonitorTimer?.cancel();
    _qualityTimer?.cancel();
    _speakingExpiryTimer?.cancel();
    final data = _data;
    data?.removeListener(_onDataChanged);
    data?.unwatchCallRoom(_room);
    if (!_leaving) {
      final call = _call;
      if (call != null) unawaited(data?.leaveCall(call.id));
      unawaited(_media?.leave());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    final data = _data;

    return Scaffold(
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
              data == null
                  ? 'Connecting…'
                  : _connectionLabel(data.realtimeState),
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
                ? _VoiceError(onRetry: _join)
                : call == null
                    ? const Center(
                        child: Text('Voice room is no longer active.'),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: _VoiceStatusCard(
                              participantCount: call.participants.length,
                              connectedPeers: _remoteStreamParticipants.length,
                            ),
                          ),
                          Expanded(
                            child: call.participants.isEmpty
                                ? const Center(
                                    child: Text('Waiting for participants…'),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      16,
                                    ),
                                    itemCount: call.participants.length,
                                    itemBuilder: (context, index) {
                                      final participant =
                                          call.participants[index];
                                      return _ParticipantTile(
                                        participant: participant,
                                        isSelf:
                                            participant.id == _selfParticipantId,
                                        speaking: _speakingParticipants
                                            .contains(participant.id),
                                        peerState: _peerStates[participant.id],
                                      );
                                    },
                                  ),
                          ),
                          _VoiceControls(
                            muted: _muted,
                            deafened: _deafened,
                            speaker: _speaker,
                            leaving: _leaving,
                            onMute: _toggleMute,
                            onDeafen: _toggleDeafen,
                            onSpeaker: _toggleSpeaker,
                            onLeave: _leave,
                          ),
                        ],
                      ),
      ),
    );
  }
}

class _VoiceStatusCard extends StatelessWidget {
  const _VoiceStatusCard({
    required this.participantCount,
    required this.connectedPeers,
  });

  final int participantCount;
  final int connectedPeers;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF12312F), Color(0xFF112638)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x3368E0CF)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFF173A3A),
            child: Icon(Icons.graphic_eq_rounded, color: Color(0xFF68E0CF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Voice connected',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '$participantCount in room • $connectedPeers remote streams',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.isSelf,
    required this.speaking,
    required this.peerState,
  });

  final CallParticipant participant;
  final bool isSelf;
  final bool speaking;
  final String? peerState;

  @override
  Widget build(BuildContext context) {
    final label = participant.displayName.trim().isNotEmpty
        ? participant.displayName
        : participant.username.trim().isNotEmpty
            ? '@${participant.username}'
            : 'Member';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        tileColor: speaking
            ? const Color(0x2468E0CF)
            : isSelf
                ? const Color(0x1468E0CF)
                : Colors.transparent,
        leading: CircleAvatar(
          backgroundColor:
              speaking ? const Color(0xFF2A6A61) : const Color(0xFF153039),
          child: speaking
              ? const Icon(Icons.graphic_eq_rounded, color: Colors.white)
              : Text(label.characters.first.toUpperCase()),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                isSelf ? '$label (You)' : label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (participant.connectionState == 'reconnecting') ...[
              const SizedBox(width: 7),
              const SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 1.4),
              ),
            ],
          ],
        ),
        subtitle: Text(
          speaking
              ? 'Speaking'
              : peerState == null
                  ? participant.connectionState
                  : '${participant.connectionState} • $peerState',
          style: TextStyle(
            color: speaking ? const Color(0xFF68E0CF) : Colors.white54,
            fontSize: 11,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (participant.deafened)
              const Icon(
                Icons.headset_off_rounded,
                size: 18,
                color: Colors.orangeAccent,
              ),
            if (participant.muted)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.mic_off_rounded,
                  size: 18,
                  color: Colors.redAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VoiceControls extends StatelessWidget {
  const _VoiceControls({
    required this.muted,
    required this.deafened,
    required this.speaker,
    required this.leaving,
    required this.onMute,
    required this.onDeafen,
    required this.onSpeaker,
    required this.onLeave,
  });

  final bool muted;
  final bool deafened;
  final bool speaker;
  final bool leaving;
  final Future<void> Function() onMute;
  final Future<void> Function() onDeafen;
  final Future<void> Function() onSpeaker;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF071015),
        border: Border(top: BorderSide(color: Color(0xFF173039))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _RoundControl(
            icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: muted ? 'Unmute' : 'Mute',
            active: muted,
            onPressed: onMute,
          ),
          _RoundControl(
            icon: deafened ? Icons.headset_off_rounded : Icons.headphones_rounded,
            label: deafened ? 'Undeafen' : 'Deafen',
            active: deafened,
            onPressed: onDeafen,
          ),
          _RoundControl(
            icon: speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
            label: 'Speaker',
            active: speaker,
            onPressed: onSpeaker,
          ),
          _RoundControl(
            icon: Icons.call_end_rounded,
            label: 'Leave',
            danger: true,
            onPressed: leaving ? null : onLeave,
          ),
        ],
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed == null ? null : () => unawaited(onPressed!()),
          style: IconButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
          ),
          icon: Icon(icon),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _VoiceError extends StatelessWidget {
  const _VoiceError({required this.onRetry});

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
              Icons.error_outline_rounded,
              size: 42,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not join this voice room.',
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

String _participantStatus(
  CallParticipant participant, {
  required RTCPeerConnectionState? peerState,
  required PeerQualitySnapshot? quality,
  required bool speaking,
  required bool isSelf,
}) {
  if (speaking) return 'Speaking';
  if (!isSelf && peerState != null) {
    if (peerState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      return 'Connection failed • retrying';
    }
    if (peerState ==
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
      return 'Reconnecting media';
    }
    if (peerState == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
      return 'Connecting media';
    }
  }
  if (!isSelf && quality != null) {
    final rtt = quality.roundTripTimeMs;
    return rtt == null
        ? 'Quality: ${quality.label}'
        : 'Quality: ${quality.label} • ${rtt.round()} ms';
  }
  return participant.connectionState;
}

String _connectionLabel(MobileRealtimeState state) {
  return switch (state) {
    MobileRealtimeState.ready => 'Realtime connected',
    MobileRealtimeState.connecting => 'Connecting…',
    MobileRealtimeState.reconnecting => 'Reconnecting…',
    MobileRealtimeState.disconnected => 'Disconnected',
  };
}
