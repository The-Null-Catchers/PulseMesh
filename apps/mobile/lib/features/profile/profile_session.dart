class ProfileSession {
  const ProfileSession({
    required this.id,
    required this.device,
    required this.browser,
    required this.os,
    required this.ip,
    required this.lastActiveAt,
    required this.createdAt,
    required this.current,
  });

  final String id;
  final String? device;
  final String? browser;
  final String? os;
  final String? ip;
  final DateTime lastActiveAt;
  final DateTime createdAt;
  final bool current;

  factory ProfileSession.fromJson(
    Map<String, dynamic> json, {
    String? currentSessionId,
  }) {
    final id = json['id'] as String?;
    final lastActive = json['last_active_at'] ?? json['lastActiveAt'];
    final created = json['created_at'] ?? json['createdAt'];
    if (id == null || lastActive is! String || created is! String) {
      throw const FormatException('Invalid session payload');
    }

    return ProfileSession(
      id: id,
      device: json['device'] as String?,
      browser: json['browser'] as String?,
      os: json['os'] as String?,
      ip: json['ip'] as String?,
      lastActiveAt: DateTime.parse(lastActive),
      createdAt: DateTime.parse(created),
      current: id == currentSessionId,
    );
  }

  String get title {
    final parts = <String>[
      if (device?.trim().isNotEmpty == true) device!.trim(),
      if (browser?.trim().isNotEmpty == true) browser!.trim(),
    ];
    return parts.isEmpty ? 'Unknown device' : parts.join(' • ');
  }

  String get subtitle {
    final parts = <String>[
      if (os?.trim().isNotEmpty == true) os!.trim(),
      if (ip?.trim().isNotEmpty == true) ip!.trim(),
    ];
    return parts.isEmpty ? 'Session details unavailable' : parts.join(' • ');
  }
}
