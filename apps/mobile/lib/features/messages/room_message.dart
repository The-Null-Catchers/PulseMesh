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

  bool get failed => status == 'failed';
  bool get sending => status == 'sending';
  bool get encrypted => encryptedPayload != null;

  String get senderLabel {
    final displayName = senderDisplayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final username = senderUsername?.trim();
    if (username != null && username.isNotEmpty) return '@$username';

    return sending ? 'You' : 'Member';
  }

  factory RoomMessage.fromRow(Map<String, Object?> row) {
    final createdAt = row['created_at'] as String?;
    final editedAt = row['edited_at'] as String?;

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
    );
  }
}
