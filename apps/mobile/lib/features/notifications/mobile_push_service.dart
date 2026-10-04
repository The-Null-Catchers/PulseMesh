import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'call_notification_action.dart';

typedef PushAccessTokenProvider = Future<String?> Function();

const _callChannelId = 'pulsemesh_calls';
const _callCategoryId = 'pulsemesh_call';
const _acceptActionId = 'call.accept';
const _declineActionId = 'call.decline';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();
bool _localNotificationsInitialized = false;
bool _backgroundHandlerRegistered = false;

@pragma('vm:entry-point')
Future<void> pulseMeshFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await _ensureLocalNotificationsInitialized();
    await _showCallNotification(message);
  } catch (_) {
    // Native Firebase configuration is optional in local/dev builds.
  }
}

void registerPulseMeshPushBackgroundHandler() {
  if (_backgroundHandlerRegistered) return;
  FirebaseMessaging.onBackgroundMessage(pulseMeshFirebaseBackgroundHandler);
  _backgroundHandlerRegistered = true;
}

Future<void> _ensureLocalNotificationsInitialized() async {
  if (_localNotificationsInitialized) return;

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  final darwin = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
    notificationCategories: <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        _callCategoryId,
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(
            _acceptActionId,
            'Accept',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.foreground,
            },
          ),
          DarwinNotificationAction.plain(
            _declineActionId,
            'Decline',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.destructive,
              DarwinNotificationActionOption.foreground,
            },
          ),
        ],
      ),
    ],
  );

  await _localNotifications.initialize(
    settings: InitializationSettings(android: android, iOS: darwin),
    onDidReceiveNotificationResponse: MobilePushService.handleNotificationResponse,
  );
  _localNotificationsInitialized = true;
}

int _notificationIdForCall(String callId) {
  var hash = 0;
  for (final unit in callId.codeUnits) {
    hash = 0x1fffffff & (hash * 31 + unit);
  }
  return hash;
}

CallNotificationAction? _callActionFromMessage(RemoteMessage message) {
  final callId = message.data['callId'];
  final conversationId = message.data['conversationId'];
  final kind = message.data['callKind'];
  if (callId == null ||
      callId.isEmpty ||
      conversationId == null ||
      conversationId.isEmpty ||
      (kind != 'voice' && kind != 'video')) {
    return null;
  }

  return CallNotificationAction(
    type: CallNotificationActionType.open,
    callId: callId,
    conversationId: conversationId,
    kind: kind,
    title: message.data['callTitle'],
  );
}

Future<void> _showCallNotification(RemoteMessage message) async {
  final action = _callActionFromMessage(message);
  if (action == null) return;

  final video = action.isVideo;
  final title = message.notification?.title ??
      (video ? 'Incoming video call' : 'Incoming voice call');
  final body = message.notification?.body ??
      message.data['body'] ??
      'Incoming PulseMesh call';

  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      _callChannelId,
      'PulseMesh calls',
      channelDescription: 'Incoming PulseMesh voice and video calls',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      timeoutAfter: 45000,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          _declineActionId,
          'Decline',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _acceptActionId,
          'Accept',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    ),
    iOS: const DarwinNotificationDetails(
      categoryIdentifier: _callCategoryId,
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  await _localNotifications.show(
    id: _notificationIdForCall(action.callId),
    title: title,
    body: body,
    notificationDetails: details,
    payload: action.toPayload(),
  );
}

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
  static final StreamController<CallNotificationAction> _callActions =
      StreamController<CallNotificationAction>.broadcast();

  static Stream<Map<String, dynamic>> get openedCallEvents =>
      _openedCallEvents.stream;
  static Stream<CallNotificationAction> get callActions => _callActions.stream;

  final PushAccessTokenProvider _accessToken;
  final FirebaseMessaging? _messagingOverride;
  final Dio _dio;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  bool _initialized = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    registerPulseMeshPushBackgroundHandler();

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      await _ensureLocalNotificationsInitialized();

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

      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
        unawaited(_showCallNotification(message));
      });

      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
      );

      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      final launchResponse = launchDetails?.notificationResponse;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchResponse != null) {
        handleNotificationResponse(launchResponse);
      }

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

  static void handleNotificationResponse(NotificationResponse response) {
    final action = CallNotificationAction.tryParse(
      response.payload,
      actionId: response.actionId,
    );
    if (action == null || _callActions.isClosed) return;
    unawaited(cancelCallNotification(action.callId));
    _callActions.add(action);
  }

  static Future<void> cancelCallNotification(String callId) async {
    if (callId.isEmpty) return;
    try {
      await _ensureLocalNotificationsInitialized();
      await _localNotifications.cancel(id: _notificationIdForCall(callId));
    } catch (_) {}
  }

  void _handleOpenedMessage(RemoteMessage message) {
    if (_disposed) return;

    final action = _callActionFromMessage(message);
    if (action == null) return;
    unawaited(cancelCallNotification(action.callId));

    final occurredAt = message.sentTime?.toUtc() ?? DateTime.now().toUtc();
    _openedCallEvents.add({
      'type': 'call.started',
      'room': 'user:push',
      'occurredAt': occurredAt.toIso8601String(),
      'payload': {
        'callId': action.callId,
        'kind': action.kind,
        'channelId': null,
        'conversationId': action.conversationId,
        'startedAt': occurredAt.toIso8601String(),
      },
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    await _tokenRefreshSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _foregroundSubscription?.cancel();
  }
}
