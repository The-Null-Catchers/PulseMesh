import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../offline/local_store.dart';
import '../../offline/models.dart';
import '../notifications/mobile_push_service.dart';

typedef MobileAccessTokenProvider = Future<String?> Function();
typedef InboxDirtyCallback = Future<void> Function();
typedef RoomDirtyCallback = Future<void> Function(RoomRef room, String eventType);
typedef TypingChangedCallback = void Function(RoomRef room, Set<String> userIds);
typedef RealtimeEventCallback = void Function(Map<String, dynamic> event);

enum MobileRealtimeState { disconnected, connecting, ready, reconnecting }

class InboxMessageSignal {
  const InboxMessageSignal({
    required this.messageId,
    required this.workspaceId,
    required this.channelId,
    required this.conversationId,
    required this.senderId,
    required this.createdAt,
  });

  final String messageId;
  final String? workspaceId;
  final String? channelId;
  final String? conversationId;
  final String senderId;
  final DateTime createdAt;

  factory InboxMessageSignal.fromRealtime(Map<String, dynamic> event) {
    if (event['type'] != 'inbox.message') {
      throw const FormatException('Not an inbox.message event');
    }

    final payload = Map<String, dynamic>.from(event['payload'] as Map);
    return InboxMessageSignal(
      messageId: payload['messageId'] as String,
      workspaceId: payload['workspaceId'] as String?,
      channelId: payload['channelId'] as String?,
      conversationId: payload['conversationId'] as String?,
      senderId: payload['senderId'] as String,
      createdAt: DateTime.parse(payload['createdAt'] as String).toUtc(),
    );
  }
}

int advanceRealtimeSequence(int current, Object? incoming) {
  if (incoming is! num) return current;
  final candidate = incoming.toInt();
  return candidate > current ? candidate : current;
}

class DioRealtimeTicketProvider {
  DioRealtimeTicketProvider({
    required String baseUrl,
    required MobileAccessTokenProvider accessToken,
    Dio? dio,
  })  : _accessToken = accessToken,
        _pushService = MobilePushService(
          baseUrl: baseUrl,
          accessToken: accessToken,
        ),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
              ),
            );

  final Dio _dio;
  final MobileAccessTokenProvider _accessToken;
  final MobilePushService _pushService;

  Future<void> initializePush() => _pushService.initialize();

  Future<void> disposePush() => _pushService.dispose();

  Future<String> createTicket() async {
    final token = await _accessToken();
    final response = await _dio.post<Map<String, dynamic>>(
      '/realtime/ticket',
      data: const <String, dynamic>{},
      options: Options(
        headers: token == null || token.isEmpty
            ? const <String, String>{}
            : {'Authorization': 'Bearer $token'},
      ),
    );

    final ticket = response.data?['ticket'] as String?;
    if (ticket == null || ticket.isEmpty) {
      throw StateError('Realtime ticket response did not include a ticket');
    }
    return ticket;
  }
}

class MobileInboxRealtimeBridge {
  MobileInboxRealtimeBridge({
    required this.webSocketUrl,
    required DioRealtimeTicketProvider ticketProvider,
    required LocalMessageStore localStore,
    required InboxDirtyCallback onInboxDirty,
    this.onRoomDirty,
    this.onTypingChanged,
    this.onEvent,
    this.onStateChanged,
    this.inboxDebounce = const Duration(milliseconds: 250),
  })  : _ticketProvider = ticketProvider,
        _localStore = localStore,
        _onInboxDirty = onInboxDirty;

  final String webSocketUrl;
  final DioRealtimeTicketProvider _ticketProvider;
  final LocalMessageStore _localStore;
  final InboxDirtyCallback _onInboxDirty;
  final RoomDirtyCallback? onRoomDirty;
  final TypingChangedCallback? onTypingChanged;
  final RealtimeEventCallback? onEvent;
  final void Function(MobileRealtimeState state)? onStateChanged;
  final Duration inboxDebounce;

  final Set<RoomRef> _rooms = <RoomRef>{};
  final Map<RoomRef, Map<String, DateTime>> _typingByRoom =
      <RoomRef, Map<String, DateTime>>{};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<Map<String, dynamic>>? _pushOpenedSubscription;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  Timer? _inboxDebounceTimer;
  Timer? _typingSweepTimer;
  bool _stopped = true;
  int _reconnectAttempt = 0;
  int _lastSequence = 0;
  RoomRef? _activeRoom;
  MobileRealtimeState _state = MobileRealtimeState.disconnected;

  MobileRealtimeState get state => _state;

  Future<void> start() async {
    if (!_stopped) return;
    _stopped = false;
    _lastSequence = await _localStore.realtimeSequence();
    _pushOpenedSubscription ??= MobilePushService.openedCallEvents.listen(
      (event) => onEvent?.call(event),
    );
    unawaited(_ticketProvider.initializePush());
    await _connect();
  }

  void watchRoom(RoomRef room) {
    _rooms.add(room);
    _activeRoom = room;

    if (_state == MobileRealtimeState.ready) {
      _send({'type': 'room.subscribe', 'room': room.cacheKey});
      _send({'type': 'view.active', 'room': room.cacheKey});
    }
  }

  void unwatchRoom(RoomRef room) {
    _rooms.remove(room);
    _typingByRoom.remove(room);
    onTypingChanged?.call(room, const <String>{});

    if (_state == MobileRealtimeState.ready) {
      _send({'type': 'room.unsubscribe', 'room': room.cacheKey});
    }

    if (_activeRoom == room) {
      _activeRoom = null;
      if (_state == MobileRealtimeState.ready) {
        _send(const {'type': 'view.active', 'room': null});
      }
    }
  }

  Future<void> stop() async {
    _stopped = true;
    for (final room in _typingByRoom.keys.toList(growable: false)) {
      onTypingChanged?.call(room, const <String>{});
    }
    _typingByRoom.clear();
    _rooms.clear();
    _activeRoom = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _inboxDebounceTimer?.cancel();
    _inboxDebounceTimer = null;
    _typingSweepTimer?.cancel();
    _typingSweepTimer = null;

    final pushSubscription = _pushOpenedSubscription;
    _pushOpenedSubscription = null;
    await pushSubscription?.cancel();
    await _ticketProvider.disposePush();

    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await channel.sink.close(1000, 'Client stopped');
    }

    _setState(MobileRealtimeState.disconnected);
  }

  Future<void> _connect() async {
    if (_stopped) return;

    _setState(
      _reconnectAttempt == 0
          ? MobileRealtimeState.connecting
          : MobileRealtimeState.reconnecting,
    );

    try {
      final ticket = await _ticketProvider.createTicket();
      if (_stopped) return;

      final baseUri = Uri.parse(webSocketUrl);
      final socketUri = baseUri.replace(
        queryParameters: {
          ...baseUri.queryParameters,
          'ticket': ticket,
        },
      );

      final channel = WebSocketChannel.connect(socketUri);
      await channel.ready;
      if (_stopped) {
        await channel.sink.close(1000, 'Client stopped');
        return;
      }

      _channel = channel;
      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    Map<String, dynamic> event;
    try {
      final decoded = jsonDecode(raw is String ? raw : raw.toString());
      event = Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return;
    }

    final type = event['type'];
    onEvent?.call(event);

    if (type == 'session.ready') {
      _send({
        'type': 'session.resume',
        'lastSequence': _lastSequence,
        'rooms': _rooms.map((room) => room.cacheKey).toList(growable: false),
      });
      return;
    }

    if (type == 'session.resumed') {
      _reconnectAttempt = 0;
      _setState(MobileRealtimeState.ready);
      _startHeartbeat();

      final activeRoom = _activeRoom;
      if (activeRoom != null) {
        _send({'type': 'view.active', 'room': activeRoom.cacheKey});
      }

      if (event['truncated'] == true) {
        _scheduleInboxRefresh();
        final roomCallback = onRoomDirty;
        if (roomCallback != null) {
          for (final room in _rooms) {
            unawaited(roomCallback(room, 'session.truncated'));
          }
        }
      }
      return;
    }

    if (type == 'inbox.message') {
      try {
        InboxMessageSignal.fromRealtime(event);
        _scheduleInboxRefresh();
      } catch (_) {
        return;
      }
    }

    if (type == 'typing.started' || type == 'typing.stopped') {
      _handleTypingEvent(event);
    }

    if (_isRoomMutation(type)) {
      final room = _roomFromRealtimeName(event['room']);
      final roomCallback = onRoomDirty;
      if (room != null &&
          _rooms.contains(room) &&
          roomCallback != null &&
          type is String) {
        unawaited(roomCallback(room, type));
      }
    }

    final nextSequence = advanceRealtimeSequence(
      _lastSequence,
      event['sequence'],
    );
    if (nextSequence != _lastSequence) {
      _lastSequence = nextSequence;
      unawaited(_localStore.writeRealtimeSequence(nextSequence));
    }
  }

  bool _isRoomMutation(Object? type) {
    return type == 'message.created' ||
        type == 'message.updated' ||
        type == 'message.deleted' ||
        type == 'reaction.created' ||
        type == 'reaction.deleted';
  }

  RoomRef? _roomFromRealtimeName(Object? value) {
    if (value is! String) return null;
    final separator = value.indexOf(':');
    if (separator <= 0 || separator == value.length - 1) return null;

    final kind = value.substring(0, separator);
    final id = value.substring(separator + 1);

    return switch (kind) {
      'channel' => RoomRef(kind: RoomKind.channel, id: id),
      'conversation' => RoomRef(kind: RoomKind.conversation, id: id),
      _ => null,
    };
  }

  void sendCallSignal({
    required String callId,
    required String targetParticipantId,
    required Map<String, dynamic> signal,
  }) {
    if (_state != MobileRealtimeState.ready) return;
    _send({
      'type': 'call.signal',
      'callId': callId,
      'targetParticipantId': targetParticipantId,
      'signal': signal,
    });
  }

  void sendCallSpeaking({
    required String callId,
    required bool speaking,
  }) {
    if (_state != MobileRealtimeState.ready) return;
    _send({
      'type': 'call.speaking',
      'callId': callId,
      'speaking': speaking,
    });
  }

  void sendTyping(RoomRef room, {required bool typing}) {
    if (_state != MobileRealtimeState.ready || !_rooms.contains(room)) return;
    _send({
      'type': typing ? 'typing.started' : 'typing.stopped',
      'room': room.cacheKey,
    });
  }

  void _handleTypingEvent(Map<String, dynamic> event) {
    final room = _roomFromRealtimeName(event['room']);
    if (room == null || !_rooms.contains(room)) return;

    final payloadValue = event['payload'];
    if (payloadValue is! Map) return;
    final payload = Map<String, dynamic>.from(payloadValue);
    final userId = payload['userId'] as String?;
    if (userId == null || userId.isEmpty) return;

    final users = _typingByRoom.putIfAbsent(
      room,
      () => <String, DateTime>{},
    );

    if (event['type'] == 'typing.stopped') {
      users.remove(userId);
    } else {
      final expiresAt = payload['expiresAt'] as String?;
      users[userId] = expiresAt == null
          ? DateTime.now().toUtc().add(const Duration(seconds: 8))
          : DateTime.parse(expiresAt).toUtc();
      _startTypingSweep();
    }

    _emitTyping(room);
  }

  void _startTypingSweep() {
    if (_typingSweepTimer?.isActive == true) return;
    _typingSweepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().toUtc();
      var hasTyping = false;

      for (final entry in _typingByRoom.entries) {
        entry.value.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
        if (entry.value.isNotEmpty) hasTyping = true;
        _emitTyping(entry.key);
      }

      if (!hasTyping) {
        _typingSweepTimer?.cancel();
        _typingSweepTimer = null;
      }
    });
  }

  void _emitTyping(RoomRef room) {
    final users = _typingByRoom[room]?.keys.toSet() ?? const <String>{};
    onTypingChanged?.call(room, users);
  }

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(message));
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_state == MobileRealtimeState.ready) {
        _send(const {'type': 'presence.heartbeat'});
      }
    });
    _send(const {'type': 'presence.heartbeat'});
  }

  void _scheduleInboxRefresh() {
    _inboxDebounceTimer?.cancel();
    _inboxDebounceTimer = Timer(inboxDebounce, () {
      unawaited(_onInboxDirty());
    });
  }

  void _handleDisconnect() {
    if (_stopped) return;
    for (final room in _typingByRoom.keys.toList(growable: false)) {
      _typingByRoom[room]?.clear();
      _emitTyping(room);
    }
    _typingSweepTimer?.cancel();
    _typingSweepTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription = null;
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped || _retryTimer?.isActive == true) return;

    _reconnectAttempt += 1;
    final exponent = _reconnectAttempt.clamp(1, 5).toInt();
    final delaySeconds = 1 << (exponent - 1);
    final delay = Duration(seconds: delaySeconds.clamp(1, 30).toInt());

    _setState(MobileRealtimeState.reconnecting);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_connect());
    });
  }

  void _setState(MobileRealtimeState next) {
    if (_state == next) return;
    _state = next;
    onStateChanged?.call(next);
  }
}
