class ChannelSummary {
  const ChannelSummary({
    required this.id,
    required this.name,
    required this.unreadCount,
    required this.kind,
    required this.visibility,
    required this.position,
  });

  final String id;
  final String name;
  final int unreadCount;
  final String kind;
  final String visibility;
  final int position;

  bool get hasUnread => unreadCount > 0;
  bool get isVoice => kind == 'voice';

  factory ChannelSummary.fromJson(Map<String, dynamic> json) {
    return ChannelSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      unreadCount: _intValue(json['unread_count']),
      kind: json['kind'] as String? ?? 'text',
      visibility: json['visibility'] as String? ?? 'public',
      position: _intValue(json['position']),
    );
  }
}

class ConversationMemberSummary {
  const ConversationMemberSummary({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory ConversationMemberSummary.fromJson(Map<String, dynamic> json) {
    return ConversationMemberSummary(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.kind,
    required this.name,
    required this.avatarUrl,
    required this.encryptionMode,
    required this.unreadCount,
    required this.members,
  });

  final String id;
  final String kind;
  final String? name;
  final String? avatarUrl;
  final String encryptionMode;
  final int unreadCount;
  final List<ConversationMemberSummary> members;

  bool get hasUnread => unreadCount > 0;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List<dynamic>? ?? const [];

    return ConversationSummary(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'direct',
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      encryptionMode: json['encryption_mode'] as String? ?? 'none',
      unreadCount: _intValue(json['unread_count']),
      members: rawMembers
          .map(
            (member) => ConversationMemberSummary.fromJson(
              Map<String, dynamic>.from(member as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class InboxSnapshot {
  const InboxSnapshot({
    required this.channels,
    required this.conversations,
  });

  final List<ChannelSummary> channels;
  final List<ConversationSummary> conversations;

  int get totalUnread {
    return channels.fold<int>(0, (sum, item) => sum + item.unreadCount) +
        conversations.fold<int>(0, (sum, item) => sum + item.unreadCount);
  }
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
