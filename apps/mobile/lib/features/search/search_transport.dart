import 'package:dio/dio.dart';

import 'search_models.dart';

typedef SearchAccessTokenProvider = Future<String?> Function();

abstract interface class SearchTransport {
  Future<SearchResults> search(String query, {int limit = 20});

  Future<String> startDirectConversation(String userId);
}

class DioSearchTransport implements SearchTransport {
  DioSearchTransport({
    required String baseUrl,
    required SearchAccessTokenProvider accessToken,
    Dio? dio,
  }) : _accessToken = accessToken,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 20),
             ),
           );

  final Dio _dio;
  final SearchAccessTokenProvider _accessToken;

  @override
  Future<SearchResults> search(String query, {int limit = 20}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/search',
      queryParameters: {'q': query.trim(), 'limit': limit},
      options: await _options(),
    );

    return SearchResults.fromJson(response.data ?? const {});
  }

  @override
  Future<String> startDirectConversation(String userId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/conversations',
      data: <String, dynamic>{
        'kind': 'direct',
        'memberIds': <String>[userId],
      },
      options: await _options(),
    );

    final id = response.data?['id'];
    if (id is! String || id.isEmpty) {
      throw StateError('Conversation response did not include an id');
    }
    return id;
  }

  Future<Options> _options() async {
    final token = await _accessToken();
    return Options(
      headers: token == null || token.isEmpty
          ? const <String, String>{}
          : <String, String>{'Authorization': 'Bearer $token'},
    );
  }
}
