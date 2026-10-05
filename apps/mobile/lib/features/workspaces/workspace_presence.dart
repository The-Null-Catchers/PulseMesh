class WorkspacePresenceMember {
  const WorkspacePresenceMember({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.status,
    required this.customText,
    required this.lastSeenAt,
    required this.connectedDevices,
    required this.activeWorkspaceId,
  });

  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String status;
  final String? customText;
  final DateTime? lastSeenAt;
  final int connectedDevices;
  final String? activeWorkspaceId;

  bool get isOnline => status != 'offline';

  factory WorkspacePresenceMember.fromJson(Map<String, dynamic> json) {
    return WorkspacePresenceMember(
      userId: json['userId'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      status: json['status'] as String? ?? 'offline',
      customText: json['customText'] as String?,
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
      connectedDevices: (json['connectedDevices'] as num?)?.toInt() ?? 0,
      activeWorkspaceId: json['activeWorkspaceId'] as String?,
    );
  }

  WorkspacePresenceMember mergeSnapshot(Map<String, dynamic> json) {
    return WorkspacePresenceMember(
      userId: userId,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl,
      status: json['status'] as String? ?? status,
      customText: json.containsKey('customText')
          ? json['customText'] as String?
          : customText,
      lastSeenAt: json.containsKey('lastSeenAt')
          ? DateTime.tryParse(json['lastSeenAt'] as String? ?? '')
          : lastSeenAt,
      connectedDevices:
          (json['connectedDevices'] as num?)?.toInt() ?? connectedDevices,
      activeWorkspaceId: json.containsKey('activeWorkspaceId')
          ? json['activeWorkspaceId'] as String?
          : activeWorkspaceId,
    );
  }
}
