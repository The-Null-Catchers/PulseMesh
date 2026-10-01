import 'package:dio/dio.dart';

typedef MessageActionAccessTokenProvider = Future<String?> Function();

abstract interface class MessageActionsTransport {
  Future<void> editMessage({
    required String messageId,
    required String body,
  });

  Future<void> deleteMessage({
    required String messageId,
    required String scope,
  });

  Future<void> setReaction({
    required String messageId,
    required String emoji,
    required bool active,
  });

  Future<void> bookmarkMessage({
    required String messageId,
    String? note,
  });

  Future<void> pinMessage({
    required String messageId,
    required bool active,
  });

  Future<void> forwardMessage({
    required String messageId,
    required String destinationKind,
    required String destinationId,
  });

  Future<List<Map<String, dynamic>>> thread(String messageId);

  Future<void> sendThreadReply({
    required String messageId,
    required String body,
  });
}

class DioMessageActionsTransport implements MessageActionsTransport {
  DioMessageActionsTransport({
    required String baseUrl,
    required MessageActionAccessTokenProvider accessToken,
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
  final MessageActionAccessTokenProvider _accessToken;

  Future<Options> _options() async {
    final token = await _accessToken();
    return Options(
      headers: token == null || token.isEmpty
          ? const <String, String>{}
          : {'Authorization': 'Bearer $token'},
    );
  }

  @override
  Future<void> editMessage({
    required String messageId,
    required String body,
  }) async {
    await _dio.patch<void>(
      '/messages/$messageId',
      data: {'body': body},
      options: await _options(),
    );
  }

  @override
  Future<void> deleteMessage({
    required String messageId,
    required String scope,
  }) async {
    await _dio.delete<void>(
      '/messages/$messageId',
      queryParameters: {'scope': scope},
      options: await _options(),
    );
  }

  @override
  Future<void> bookmarkMessage({
    required String messageId,
    String? note,
  }) async {
    await _dio.put<void>(
      '/messages/$messageId/bookmark',
      data: {'note': note},
      options: await _options(),
    );
  }

  @override
  Future<void> pinMessage({
    required String messageId,
    required bool active,
  }) async {
    final path = '/messages/$messageId/pin';
    final options = await _options();
    if (active) {
      await _dio.post<void>(path, options: options);
    } else {
      await _dio.delete<void>(path, options: options);
    }
  }

  @override
  Future<void> forwardMessage({
    required String messageId,
    required String destinationKind,
    required String destinationId,
  }) async {
    await _dio.post<void>(
      '/messages/$messageId/forward',
      data: destinationKind == 'channel'
          ? {'channelId': destinationId}
          : {'conversationId': destinationId},
      options: await _options(),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> thread(String messageId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/messages/$messageId/thread',
      options: await _options(),
    );
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  @override
  Future<void> sendThreadReply({
    required String messageId,
    required String body,
  }) async {
    await _dio.post<void>(
      '/messages/$messageId/thread',
      data: {'body': body},
      options: await _options(),
    );
  }

  @override
  Future<void> setReaction({
    required String messageId,
    required String emoji,
    required bool active,
  }) async {
    final encodedEmoji = Uri.encodeComponent(emoji);
    final path = '/messages/$messageId/reactions/$encodedEmoji';
    final options = await _options();

    if (active) {
      await _dio.put<void>(path, options: options);
    } else {
      await _dio.delete<void>(path, options: options);
    }
  }
}

