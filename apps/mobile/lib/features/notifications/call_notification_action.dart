import 'dart:convert';

enum CallNotificationActionType { open, accept, decline }

class CallNotificationAction {
  const CallNotificationAction({
    required this.type,
    required this.callId,
    required this.conversationId,
    required this.kind,
    this.title,
  });

  final CallNotificationActionType type;
  final String callId;
  final String conversationId;
  final String kind;
  final String? title;

  bool get isVideo => kind == 'video';

  String toPayload() => jsonEncode({
        'callId': callId,
        'conversationId': conversationId,
        'kind': kind,
        if (title != null && title!.isNotEmpty) 'title': title,
      });

  static CallNotificationAction? tryParse(
    String? payload, {
    String? actionId,
  }) {
    if (payload == null || payload.isEmpty) return null;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);
      final callId = data['callId'] as String?;
      final conversationId = data['conversationId'] as String?;
      final kind = data['kind'] as String?;
      if (callId == null ||
          callId.isEmpty ||
          conversationId == null ||
          conversationId.isEmpty ||
          (kind != 'voice' && kind != 'video')) {
        return null;
      }

      final type = switch (actionId) {
        'call.accept' => CallNotificationActionType.accept,
        'call.decline' => CallNotificationActionType.decline,
        _ => CallNotificationActionType.open,
      };

      return CallNotificationAction(
        type: type,
        callId: callId,
        conversationId: conversationId,
        kind: kind!,
        title: data['title'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
