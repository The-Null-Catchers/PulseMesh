import 'package:dio/dio.dart';

import 'profile_model.dart';

typedef ProfileAccessTokenProvider = Future<String?> Function();

abstract interface class ProfileTransport {
  Future<UserProfile> fetchProfile();

  Future<UserProfile> updateProfile({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? timezone,
    String? statusText,
  });
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
  Future<UserProfile> updateProfile({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? timezone,
    String? statusText,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/profile',
      data: <String, dynamic>{
        if (username != null) 'username': username,
        if (displayName != null) 'displayName': displayName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (bio != null) 'bio': bio,
        if (timezone != null) 'timezone': timezone,
        if (statusText != null) 'statusText': statusText,
      },
      options: await _options(),
    );
    return UserProfile.fromJson(response.data ?? const {});
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
