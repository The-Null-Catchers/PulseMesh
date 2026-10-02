import 'package:dio/dio.dart';

import '../../offline/sync_transport.dart';

class CallParticipant {
  const CallParticipant({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.muted,
    required this.deafened,
    required this.cameraEnabled,
    required this.screenSharing,
    required this.connectionState,
    required this.joinedAt,
  });

  final String id;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool muted;
  final bool deafened;
  final bool cameraEnabled;
  final bool screenSharing;
  final String connectionState;
  final DateTime joinedAt;

  factory CallParticipant.fromJson(Map<String, dynamic> json) {
    return CallParticipant(
      id: json['id'] as String,
      userId: json['userId'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      muted: json['muted'] as bool? ?? false,
      deafened: json['deafened'] as bool? ?? false,
      cameraEnabled: json['cameraEnabled'] as bool? ?? false,
      screenSharing: json['screenSharing'] as bool? ?? false,
      connectionState: json['connectionState'] as String? ?? 'connected',
      joinedAt: DateTime.parse(json['joinedAt'] as String).toUtc(),
    );
  }
}

class ActiveCall {
  const ActiveCall({
    required this.id,
    required this.channelId,
    required this.conversationId,
    required this.createdBy,
    required this.kind,
    required this.status,
    required this.provider,
    required this.startedAt,
    required this.endedAt,
    required this.participants,
  });

  final String id;
  final String? channelId;
  final String? conversationId;
  final String createdBy;
  final String kind;
  final String status;
  final String provider;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<CallParticipant> participants;

  factory ActiveCall.fromJson(Map<String, dynamic> json) {
    final raw = json['participants'] as List<dynamic>? ?? const [];
    return ActiveCall(
      id: json['id'] as String,
      channelId: json['channelId'] as String?,
      conversationId: json['conversationId'] as String?,
      createdBy: json['createdBy'] as String,
      kind: json['kind'] as String? ?? 'voice',
      status: json['status'] as String? ?? 'active',
      provider: json['provider'] as String? ?? 'mesh',
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      endedAt: json['endedAt'] == null
          ? null
          : DateTime.parse(json['endedAt'] as String).toUtc(),
      participants: raw
          .map((item) => CallParticipant.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(growable: false),
    );
  }
}

abstract interface class CallTransport {
  Future<List<Map<String, dynamic>>> iceServers();
  Future<ActiveCall> startVoiceCall(String channelId);
  Future<ActiveCall> startConversationCall(
    String conversationId, {
    required String kind,
  });
  Future<ActiveCall> refreshCall(String callId);
  Future<CallParticipant> updateParticipant(
    String callId, {
    bool? muted,
    bool? deafened,
    bool? cameraEnabled,
    bool? screenSharing,
    String? connectionState,
  });
  Future<void> leave(String callId);
}

class DioCallTransport implements CallTransport {
  DioCallTransport({
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
  Future<List<Map<String, dynamic>>> iceServers() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/calls/ice-config',
      options: await _options(),
    );
    final raw = response.data?['iceServers'] as List<dynamic>? ?? const [];
    return raw
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  @override
  Future<ActiveCall> startVoiceCall(String channelId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/calls',
      data: {'channelId': channelId, 'kind': 'voice'},
      options: await _options(),
    );
    return ActiveCall.fromJson(response.data ?? const {});
  }

  @override
  @override
  Future<ActiveCall> startConversationCall(
    String conversationId, {
    required String kind,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/calls',
      data: {'conversationId': conversationId, 'kind': kind},
      options: await _options(),
    );
    return ActiveCall.fromJson(response.data ?? const {});
  }

  @override
  Future<ActiveCall> refreshCall(String callId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/calls/$callId',
      options: await _options(),
    );
    return ActiveCall.fromJson(response.data ?? const {});
  }

  @override
  Future<CallParticipant> updateParticipant(
    String callId, {
    bool? muted,
    bool? deafened,
    bool? cameraEnabled,
    bool? screenSharing,
    String? connectionState,
  }) async {
    final patch = <String, dynamic>{};
    if (muted != null) patch['muted'] = muted;
    if (deafened != null) patch['deafened'] = deafened;
    if (cameraEnabled != null) patch['cameraEnabled'] = cameraEnabled;
    if (screenSharing != null) patch['screenSharing'] = screenSharing;
    if (connectionState != null) {
      patch['connectionState'] = connectionState;
    }

    final response = await _dio.patch<Map<String, dynamic>>(
      '/calls/$callId/participant',
      data: patch,
      options: await _options(),
    );
    return CallParticipant.fromJson(response.data ?? const {});
  }

  @override
  Future<void> leave(String callId) async {
    await _dio.post<void>(
      '/calls/$callId/leave',
      data: const <String, dynamic>{},
      options: await _options(),
    );
  }
}
