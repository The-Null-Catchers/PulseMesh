import 'package:dio/dio.dart';

import 'auth_models.dart';

class AuthTransportException implements Exception {
  const AuthTransportException({
    required this.message,
    this.statusCode,
    this.code,
  });

  final String message;
  final int? statusCode;
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'AuthTransportException($statusCode, $code, $message)';
}

abstract interface class AuthTransport {
  Future<AuthTokens> login(LoginCredentials credentials);

  Future<AuthTokens> register(RegisterCredentials credentials);

  Future<AuthTokens> refresh(String refreshToken);

  Future<void> logout(String accessToken);
}

class DioAuthTransport implements AuthTransport {
  DioAuthTransport({
    required String baseUrl,
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
              ),
            );

  final Dio _dio;

  @override
  Future<AuthTokens> login(LoginCredentials credentials) async {
    return _tokensRequest(
      '/auth/login',
      credentials.toJson(),
    );
  }

  @override
  Future<AuthTokens> register(RegisterCredentials credentials) async {
    return _tokensRequest(
      '/auth/register',
      credentials.toJson(),
    );
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    return _tokensRequest(
      '/auth/refresh',
      {'refreshToken': refreshToken},
    );
  }

  @override
  Future<void> logout(String accessToken) async {
    try {
      await _dio.post<void>(
        '/auth/logout',
        data: const <String, dynamic>{},
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
      );
    } on DioException catch (error) {
      throw _mapDioError(error);
    }
  }

  Future<AuthTokens> _tokensRequest(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
      );
      final data = response.data;
      if (data == null) {
        throw const AuthTransportException(
          message: 'Authentication returned an empty response',
        );
      }
      return AuthTokens.fromJson(data);
    } on DioException catch (error) {
      throw _mapDioError(error);
    }
  }

  AuthTransportException _mapDioError(DioException error) {
    final data = error.response?.data;
    String? code;
    String message = error.message ?? 'Authentication request failed';

    if (data is Map) {
      final json = Map<String, dynamic>.from(data);
      code = json['code'] as String?;
      message =
          json['message'] as String? ??
          json['error'] as String? ??
          message;
    }

    return AuthTransportException(
      statusCode: error.response?.statusCode,
      code: code,
      message: message,
    );
  }
}
