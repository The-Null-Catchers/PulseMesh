import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

typedef PushAccessTokenProvider = Future<String?> Function();

class MobilePushService {
  MobilePushService({
    required String baseUrl,
    required PushAccessTokenProvider accessToken,
    FirebaseMessaging? messaging,
    Dio? dio,
  })  : _accessToken = accessToken,
        _messagingOverride = messaging,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
              ),
            );

  static final StreamController<Map<String, dynamic>> _openedCallEvents =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get openedCallEvents =>
      _openedCallEvents.stream;

  final PushAccessTokenProvider _accessToken;
  final FirebaseMessaging? _messagingOverride;
  final Dio _dio;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final messaging = _messagingOverride ?? FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }

      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token));
      });

      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
      );

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleOpenedMessage(initialMessage);
      }
    } catch (_) {
      // Local/dev builds may intentionally omit native Firebase config.
      // Push support is optional and must never prevent authenticated startup.
    }
  }

  Future<void> _registerToken(String token) async {
    if (_disposed || token.isEmpty) return;

    try {
      final accessToken = await _accessToken();
      if (accessToken == null || accessToken.isEmpty) return;

      await _dio.post<void>(
        '/notification-devices',
        data: {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'token': token,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
      );
    } catch (_) {
      // Registration is retried on token refresh or the next app session.
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    if (_disposed) return;

    final callId = message.data['callId'];
    final kind = message.data['callKind'];
    final conversationId = message.data['conversationId'];
    if (callId == null ||
        callId.isEmpty ||
        conversationId == null ||
        conversationId.isEmpty ||
        (kind != 'voice' && kind != 'video')) {
      return;
    }

    final occurredAt = message.sentTime?.toUtc() ?? DateTime.now().toUtc();
    _openedCallEvents.add({
      'type': 'call.started',
      'room': 'user:push',
      'occurredAt': occurredAt.toIso8601String(),
      'payload': {
        'callId': callId,
        'kind': kind,
        'channelId': null,
        'conversationId': conversationId,
        'startedAt': occurredAt.toIso8601String(),
      },
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    await _tokenRefreshSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}
