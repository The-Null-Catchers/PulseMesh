class SavedMessageSender {
  const SavedMessageSender({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory SavedMessageSender.fromJson(Map<String, dynamic> json) {
    return SavedMessageSender(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class SavedMessageContent {
  const SavedMessageContent({
    required this.id,
    required this.channelId,
    required this.conversationId,
    required this.body,
    required this.createdAt,
    required this.editedAt,
    required this.sender,
  });

  final String id;
  final String? channelId;
  final String? conversationId;
  final String body;
  final DateTime createdAt;
  final DateTime? editedAt;
  final SavedMessageSender sender;

  factory SavedMessageContent.fromJson(Map<String, dynamic> json) {
    final senderValue = json['sender'];
    return SavedMessageContent(
      id: json['id'] as String? ?? '',
      channelId: json['channelId'] as String?,
      conversationId: json['conversationId'] as String?,
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      editedAt: DateTime.tryParse(json['editedAt'] as String? ?? ''),
      sender: SavedMessageSender.fromJson(
        senderValue is Map
            ? Map<String, dynamic>.from(senderValue)
            : const <String, dynamic>{},
      ),
    );
  }
}

class SavedMessage {
  const SavedMessage({
    required this.messageId,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.message,
  });

  final String messageId;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SavedMessageContent message;

  factory SavedMessage.fromJson(Map<String, dynamic> json) {
    final messageValue = json['message'];
    return SavedMessage(
      messageId: json['messageId'] as String? ?? '',
      note: json['note'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      message: SavedMessageContent.fromJson(
        messageValue is Map
            ? Map<String, dynamic>.from(messageValue)
            : const <String, dynamic>{},
      ),
    );
  }
}
