class SearchMessageResult {
  const SearchMessageResult({
    required this.id,
    required this.body,
    required this.channelId,
    required this.conversationId,
    required this.createdAt,
    required this.username,
    required this.displayName,
  });

  final String id;
  final String body;
  final String? channelId;
  final String? conversationId;
  final DateTime createdAt;
  final String username;
  final String displayName;

  factory SearchMessageResult.fromJson(Map<String, dynamic> json) {
    return SearchMessageResult(
      id: json['id'] as String? ?? '',
      body: json['body'] as String? ?? '',
      channelId: json['channel_id'] as String?,
      conversationId: json['conversation_id'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
    );
  }
}

class SearchUserResult {
  const SearchUserResult({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory SearchUserResult.fromJson(Map<String, dynamic> json) {
    return SearchUserResult(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class SearchChannelResult {
  const SearchChannelResult({
    required this.id,
    required this.name,
    required this.workspaceId,
  });

  final String id;
  final String name;
  final String workspaceId;

  factory SearchChannelResult.fromJson(Map<String, dynamic> json) {
    return SearchChannelResult(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      workspaceId: json['workspace_id'] as String? ?? '',
    );
  }
}

class SearchResults {
  const SearchResults({
    required this.messages,
    required this.users,
    required this.channels,
  });

  final List<SearchMessageResult> messages;
  final List<SearchUserResult> users;
  final List<SearchChannelResult> channels;

  bool get isEmpty => messages.isEmpty && users.isEmpty && channels.isEmpty;

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(String key, T Function(Map<String, dynamic>) parser) {
      final values = json[key] as List<dynamic>? ?? const [];
      return values
          .whereType<Map>()
          .map((value) => parser(Map<String, dynamic>.from(value)))
          .toList(growable: false);
    }

    return SearchResults(
      messages: parseList('messages', SearchMessageResult.fromJson),
      users: parseList('users', SearchUserResult.fromJson),
      channels: parseList('channels', SearchChannelResult.fromJson),
    );
  }
}
