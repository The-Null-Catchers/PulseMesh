import 'dart:convert';

class RoomAttachment {
  const RoomAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.hasThumbnail,
  });

  final String id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final bool hasThumbnail;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');

  factory RoomAttachment.fromJson(Map<String, dynamic> json) {
    int? optionalInt(Object? value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    final rawSize = json['sizeBytes'];
    return RoomAttachment(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Attachment',
      mimeType: json['mimeType'] as String? ??
          json['declaredMimeType'] as String? ??
          'application/octet-stream',
      sizeBytes: rawSize is num
          ? rawSize.toInt()
          : int.tryParse(rawSize?.toString() ?? '') ?? 0,
      width: optionalInt(json['width']),
      height: optionalInt(json['height']),
      durationMs: optionalInt(json['durationMs']),
      hasThumbnail: json['hasThumbnail'] as bool? ?? false,
    );
  }
}

class RoomReaction {
  const RoomReaction({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
  });

  final String emoji;
  final int count;
  final bool reactedByMe;

  factory RoomReaction.fromJson(Map<String, dynamic> json) {
    final rawCount = json['count'];
    return RoomReaction(
      emoji: json['emoji'] as String? ?? '',
      count: rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '') ?? 0,
      reactedByMe: json['reactedByMe'] as bool? ?? false,
    );
  }
}

class RoomMessage {
  const RoomMessage({
    required this.localId,
    required this.serverId,
    required this.clientMessageId,
    required this.body,
    required this.senderId,
    required this.senderUsername,
    required this.senderDisplayName,
    required this.senderAvatarUrl,
    required this.createdAt,
    required this.editedAt,
    required this.status,
    required this.encryptionVersion,
    required this.encryptedPayload,
    required this.replyToMessageId,
    required this.attachments,
    required this.reactions,
  });

  final String localId;
  final String? serverId;
  final String? clientMessageId;
  final String body;
  final String? senderId;
  final String? senderUsername;
  final String? senderDisplayName;
  final String? senderAvatarUrl;
  final DateTime createdAt;
  final DateTime? editedAt;
  final String status;
  final String? encryptionVersion;
  final String? encryptedPayload;
  final String? replyToMessageId;
  final List<RoomAttachment> attachments;
  final List<RoomReaction> reactions;

  bool get failed => status == 'failed';
  bool get sending => status == 'sending';
  bool get encrypted => encryptedPayload != null;

  String get senderLabel {
    final displayName = senderDisplayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final username = senderUsername?.trim();
    if (username != null && username.isNotEmpty) return '@$username';

    if (clientMessageId != null) return 'You';
    return 'Member';
  }

  factory RoomMessage.fromRow(Map<String, Object?> row) {
    final createdAt = row['created_at'] as String?;
    final editedAt = row['edited_at'] as String?;
    final rawAttachments = row['attachments_json'] as String? ?? '[]';
    final decodedAttachments = jsonDecode(rawAttachments) as List<dynamic>;
    final rawReactions = row['reactions_json'] as String? ?? '[]';
    final decodedReactions = jsonDecode(rawReactions) as List<dynamic>;

    return RoomMessage(
      localId: row['local_id']! as String,
      serverId: row['server_id'] as String?,
      clientMessageId: row['client_message_id'] as String?,
      body: row['body'] as String? ?? '',
      senderId: row['sender_id'] as String?,
      senderUsername: row['sender_username'] as String?,
      senderDisplayName: row['sender_display_name'] as String?,
      senderAvatarUrl: row['sender_avatar_url'] as String?,
      createdAt: createdAt == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.parse(createdAt).toLocal(),
      editedAt: editedAt == null ? null : DateTime.parse(editedAt).toLocal(),
      status: row['status'] as String? ?? 'sent',
      encryptionVersion: row['encryption_version'] as String?,
      encryptedPayload: row['encrypted_payload'] as String?,
      replyToMessageId: row['reply_to_message_id'] as String?,
      attachments: decodedAttachments
          .map(
            (item) => RoomAttachment.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where((attachment) => attachment.id.isNotEmpty)
          .toList(growable: false),
      reactions: decodedReactions
          .map(
            (item) => RoomReaction.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where((reaction) => reaction.emoji.isNotEmpty && reaction.count > 0)
          .toList(growable: false),
    );
  }
}
