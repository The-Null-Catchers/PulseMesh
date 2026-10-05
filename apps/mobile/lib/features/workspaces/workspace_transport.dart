import 'package:dio/dio.dart';

import 'workspace_models.dart';
import 'workspace_presence.dart';

typedef WorkspaceAccessTokenProvider = Future<String?> Function();

abstract interface class WorkspaceTransport {
  Future<List<WorkspaceSummary>> listWorkspaces();

  Future<List<WorkspacePresenceMember>> listPresence(String workspaceId);
}

class DioWorkspaceTransport implements WorkspaceTransport {
  DioWorkspaceTransport({
    required String baseUrl,
    required WorkspaceAccessTokenProvider accessToken,
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
  final WorkspaceAccessTokenProvider _accessToken;

  Future<Options> _options() async {
    final token = await _accessToken();
    return Options(
      headers: token == null || token.isEmpty
          ? const <String, String>{}
          : {'Authorization': 'Bearer $token'},
    );
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/workspaces',
      options: await _options(),
    );
    final items = response.data?['items'] as List<dynamic>? ?? const [];

    return items
        .map(
          (item) => WorkspaceSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<WorkspacePresenceMember>> listPresence(String workspaceId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/workspaces/$workspaceId/presence',
      options: await _options(),
    );
    final items = response.data?['items'] as List<dynamic>? ?? const [];
    return items
        .map(
          (item) => WorkspacePresenceMember.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }
}
