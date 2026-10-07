import 'package:dio/dio.dart';

typedef GroupAccessTokenProvider = Future<String?> Function();

abstract interface class GroupManagementTransport {
  Future<void> renameGroup({required String conversationId, required String name});
  Future<void> addMember({required String conversationId, required String userId});
  Future<void> removeMember({required String conversationId, required String memberId});
  Future<void> setMemberRole({
    required String conversationId,
    required String memberId,
    required String role,
  });
}

class DioGroupManagementTransport implements GroupManagementTransport {
  DioGroupManagementTransport({
    required String baseUrl,
    required GroupAccessTokenProvider accessToken,
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
  final GroupAccessTokenProvider _accessToken;

  Future<Options> _options() async {
    final token = await _accessToken();
    return Options(
      headers: token == null || token.isEmpty
          ? const <String, String>{}
          : {'Authorization': 'Bearer $token'},
    );
  }

  @override
  Future<void> renameGroup({
    required String conversationId,
    required String name,
  }) async {
    await _dio.patch<void>(
      '/conversations/$conversationId',
      data: {'name': name.trim()},
      options: await _options(),
    );
  }

  @override
  Future<void> addMember({
    required String conversationId,
    required String userId,
  }) async {
    await _dio.post<void>(
      '/conversations/$conversationId/members',
      data: {'userId': userId},
      options: await _options(),
    );
  }

  @override
  Future<void> removeMember({
    required String conversationId,
    required String memberId,
  }) async {
    await _dio.delete<void>(
      '/conversations/$conversationId/members/$memberId',
      options: await _options(),
    );
  }

  @override
  Future<void> setMemberRole({
    required String conversationId,
    required String memberId,
    required String role,
  }) async {
    await _dio.put<void>(
      '/conversations/$conversationId/members/$memberId/role',
      data: {'role': role},
      options: await _options(),
    );
  }
}
