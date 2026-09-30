import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../offline/local_store.dart';

typedef MobileAccessTokenProvider = Future<String?> Function();
typedef InboxDirtyCallback = Future<void> Function();

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
    this.onStateChanged,
    this.inboxDebounce = const Duration(milliseconds: 250),
  })  : _ticketProvider = ticketProvider,
        _localStore = localStore,
        _onInboxDirty = onInboxDirty;

  final String webSocketUrl;
  final DioRealtimeTicketProvider _ticketProvider;
  final LocalMessageStore _localStore;
  final InboxDirtyCallback _onInboxDirty;
  final void Function(MobileRealtimeState state)? onStateChanged;
  final Duration inboxDebounce;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  Timer? _inboxDebounceTimer;
  bool _stopped = true;
  int _reconnectAttempt = 0;
  int _lastSequence = 0;
  MobileRealtimeState _state = MobileRealtimeState.disconnected;

  MobileRealtimeState get state => _state;

  Future<void> start() async {
    if (!_stopped) return;
    _stopped = false;
    _lastSequence = await _localStore.realtimeSequence();
    await _connect();
  }

  Future<void> stop() async {
    _stopped = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _inboxDebounceTimer?.cancel();
    _inboxDebounceTimer = null;

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

    if (type == 'session.ready') {
      _send({
        'type': 'session.resume',
        'lastSequence': _lastSequence,
        'rooms': const <String>[],
      });
      return;
    }

    if (type == 'session.resumed') {
      _reconnectAttempt = 0;
      _setState(MobileRealtimeState.ready);
      _startHeartbeat();

      if (event['truncated'] == true) {
        _scheduleInboxRefresh();
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

    final nextSequence = advanceRealtimeSequence(
      _lastSequence,
      event['sequence'],
    );
    if (nextSequence != _lastSequence) {
      _lastSequence = nextSequence;
      unawaited(_localStore.writeRealtimeSequence(nextSequence));
    }
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription = null;
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped || _retryTimer?.isActive == true) return;

    _reconnectAttempt += 1;
    final exponent = _reconnectAttempt.clamp(1, 5);
    final delaySeconds = 1 << (exponent - 1);
    final delay = Duration(seconds: delaySeconds.clamp(1, 30));

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
