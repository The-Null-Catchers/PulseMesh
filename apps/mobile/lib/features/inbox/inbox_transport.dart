import 'package:dio/dio.dart';

import 'inbox_models.dart';

typedef InboxAccessTokenProvider = Future<String?> Function();

abstract interface class InboxTransport {
  Future<List<ChannelSummary>> channels(String workspaceId);

  Future<List<ConversationSummary>> conversations();

  Future<void> markChannelRead({
    required String channelId,
    required String lastReadMessageId,
  });

  Future<void> markConversationRead({
    required String conversationId,
    required String lastReadMessageId,
  });
}

class DioInboxTransport implements InboxTransport {
  DioInboxTransport({
    required String baseUrl,
    required InboxAccessTokenProvider accessToken,
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
  final InboxAccessTokenProvider _accessToken;

  Future<Options> _options() async {
    final token = await _accessToken();
    return Options(
      headers: token == null || token.isEmpty
          ? const <String, String>{}
          : {'Authorization': 'Bearer $token'},
    );
  }

  @override
  Future<List<ChannelSummary>> channels(String workspaceId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/workspaces/$workspaceId/channels',
      options: await _options(),
    );
    final items = response.data?['items'] as List<dynamic>? ?? const [];

    return items
        .map(
          (item) => ChannelSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ConversationSummary>> conversations() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/conversations',
      options: await _options(),
    );
    final items = response.data?['items'] as List<dynamic>? ?? const [];

    return items
        .map(
          (item) => ConversationSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markChannelRead({
    required String channelId,
    required String lastReadMessageId,
  }) {
    return _putReadState({
      'channelId': channelId,
      'lastReadMessageId': lastReadMessageId,
    });
  }

  @override
  Future<void> markConversationRead({
    required String conversationId,
    required String lastReadMessageId,
  }) {
    return _putReadState({
      'conversationId': conversationId,
      'lastReadMessageId': lastReadMessageId,
    });
  }

  Future<void> _putReadState(Map<String, dynamic> body) async {
    await _dio.put<void>(
      '/read-state',
      data: body,
      options: await _options(),
    );
  }
}
