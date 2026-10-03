import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../auth/auth_session_controller.dart';
import '../../config/app_config.dart';

typedef PushDeepLinkHandler = void Function(String deepLink);

class MobilePushService {
  MobilePushService({
    required AuthSessionController authSession,
    required AppConfig config,
    required PushDeepLinkHandler onDeepLink,
    FirebaseMessaging? messaging,
    Dio? dio,
  })  : _authSession = authSession,
        _onDeepLink = onDeepLink,
        _messaging = messaging ?? FirebaseMessaging.instance,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: config.apiBaseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
              ),
            );

  final AuthSessionController _authSession;
  final PushDeepLinkHandler _onDeepLink;
  final FirebaseMessaging _messaging;
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

      final permission = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }

      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token));
      });

      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
      );

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleOpenedMessage(initialMessage);
      }
    } catch (_) {
      // Native Firebase configuration may not be present in local/dev builds.
      // Push support remains optional and must never prevent app startup.
    }
  }

  Future<void> _registerToken(String token) async {
    if (_disposed || token.isEmpty) return;

    try {
      final accessToken = await _authSession.accessToken();
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
      // Token registration is retried when Firebase rotates the token or on the
      // next authenticated app start.
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    if (_disposed) return;
    final deepLink = message.data['deepLink'];
    if (deepLink == null || deepLink.isEmpty) return;
    _onDeepLink(deepLink);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _tokenRefreshSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}
