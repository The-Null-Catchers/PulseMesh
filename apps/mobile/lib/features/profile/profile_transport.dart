import 'dart:convert';

import 'package:dio/dio.dart';

import 'profile_model.dart';
import 'profile_session.dart';

typedef ProfileAccessTokenProvider = Future<String?> Function();

abstract interface class ProfileTransport {
  Future<UserProfile> fetchProfile();

  Future<UserProfile> updateProfile(Map<String, dynamic> changes);

  Future<List<ProfileSession>> fetchSessions();

  Future<void> revokeSession(String sessionId);
}

class DioProfileTransport implements ProfileTransport {
  DioProfileTransport({
    required String baseUrl,
    required ProfileAccessTokenProvider accessToken,
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
  final ProfileAccessTokenProvider _accessToken;

  @override
  Future<UserProfile> fetchProfile() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/profile',
      options: await _options(),
    );
    return UserProfile.fromJson(response.data ?? const {});
  }

  @override
  Future<UserProfile> updateProfile(Map<String, dynamic> changes) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/profile',
      data: changes,
      options: await _options(),
    );
    return UserProfile.fromJson(response.data ?? const {});
  }

  @override
  Future<List<ProfileSession>> fetchSessions() async {
    final token = await _accessToken();
    final response = await _dio.get<Map<String, dynamic>>(
      '/auth/sessions',
      options: _optionsForToken(token),
    );
    final items = response.data?['items'];
    if (items is! List) return const <ProfileSession>[];
    final currentSessionId = _sessionIdFromAccessToken(token);
    return items
        .whereType<Map>()
        .map(
          (item) => ProfileSession.fromJson(
            Map<String, dynamic>.from(item),
            currentSessionId: currentSessionId,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> revokeSession(String sessionId) async {
    await _dio.delete<void>(
      '/auth/sessions/$sessionId',
      options: await _options(),
    );
  }

  Future<Options> _options() async => _optionsForToken(await _accessToken());

  Options _optionsForToken(String? token) {
    return Options(
      headers: token == null || token.isEmpty
          ? const <String, String>{}
          : <String, String>{'Authorization': 'Bearer $token'},
    );
  }

  String? _sessionIdFromAccessToken(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      return decoded['sessionId'] as String?;
    } catch (_) {
      return null;
    }
  }
}
