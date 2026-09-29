import 'package:dio/dio.dart';

import 'models.dart';

typedef AccessTokenProvider = Future<String?> Function();

abstract interface class MessageSyncTransport {
  Future<String> currentCursor(RoomRef room);

  Future<List<Map<String, dynamic>>> recentMessages(
    RoomRef room, {
    int limit = 50,
  });

  Future<SendAcknowledgement> send(
    PendingOutgoingMessage message,
  );

  Future<SyncPage> sync(
    RoomRef room, {
    required String after,
    int limit = 100,
  });
}

class DioMessageSyncTransport implements MessageSyncTransport {
  DioMessageSyncTransport({
    required String baseUrl,
    required AccessTokenProvider accessToken,
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
  final AccessTokenProvider _accessToken;

  Future<Options> _options() async {
    final token = await _accessToken();
    return Options(
      headers: token == null || token.isEmpty
          ? const <String, String>{}
          : {'Authorization': 'Bearer $token'},
    );
  }

  @override
  Future<String> currentCursor(RoomRef room) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${room.apiBase}/messages/sync/cursor',
      options: await _options(),
    );
    return response.data?['cursor'] as String? ?? '0';
  }

  @override
  Future<List<Map<String, dynamic>>> recentMessages(
    RoomRef room, {
    int limit = 50,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${room.apiBase}/messages',
      queryParameters: {'limit': limit},
      options: await _options(),
    );
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  @override
  Future<SendAcknowledgement> send(
    PendingOutgoingMessage message,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '${message.room.apiBase}/messages',
      data: {
        'clientMessageId': message.clientMessageId,
        'body': message.body,
        if (message.encryptionVersion != null)
          'encryptionVersion': message.encryptionVersion,
        if (message.encryptedPayload != null)
          'encryptedPayload': message.encryptedPayload,
        if (message.replyToMessageId != null)
          'replyToMessageId': message.replyToMessageId,
        'attachmentIds': message.attachmentIds,
      },
      options: await _options(),
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Message send returned an empty response');
    }

    return SendAcknowledgement(
      id: data['id'] as String,
      clientMessageId:
          data['clientMessageId'] as String? ?? message.clientMessageId,
      createdAt: DateTime.parse(data['createdAt'] as String).toUtc(),
    );
  }

  @override
  Future<SyncPage> sync(
    RoomRef room, {
    required String after,
    int limit = 100,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${room.apiBase}/messages/sync',
      queryParameters: {'after': after, 'limit': limit},
      options: await _options(),
    );

    return SyncPage.fromJson(response.data ?? const {});
  }
}
