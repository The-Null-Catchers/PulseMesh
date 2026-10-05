class PresenceSnapshot {
  const PresenceSnapshot({
    required this.userId,
    required this.status,
    required this.customText,
    required this.lastSeenAt,
    required this.connectedDevices,
    required this.activeWorkspaceId,
  });

  final String userId;
  final String status;
  final String? customText;
  final DateTime? lastSeenAt;
  final int connectedDevices;
  final String? activeWorkspaceId;

  bool get isOnline => status != 'offline';

  factory PresenceSnapshot.fromJson(Map<String, dynamic> json) {
    return PresenceSnapshot(
      userId: json['userId'] as String? ?? '',
      status: json['status'] as String? ?? 'offline',
      customText: json['customText'] as String?,
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
      connectedDevices: (json['connectedDevices'] as num?)?.toInt() ?? 0,
      activeWorkspaceId: json['activeWorkspaceId'] as String?,
    );
  }
}
