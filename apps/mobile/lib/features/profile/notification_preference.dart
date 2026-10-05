class NotificationQuietHours {
  const NotificationQuietHours({
    required this.start,
    required this.end,
    required this.timezone,
  });

  final String start;
  final String end;
  final String timezone;

  factory NotificationQuietHours.fromJson(Map<String, dynamic> json) {
    return NotificationQuietHours(
      start: json['start'] as String? ?? '22:00',
      end: json['end'] as String? ?? '08:00',
      timezone: json['timezone'] as String? ?? 'UTC',
    );
  }

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'timezone': timezone,
      };
}

class NotificationPreference {
  const NotificationPreference({
    required this.level,
    this.quietHours,
  });

  final String level;
  final NotificationQuietHours? quietHours;

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    final quietHoursValue = json['quiet_hours'] ?? json['quietHours'];
    return NotificationPreference(
      level: json['level'] as String? ?? 'all',
      quietHours: quietHoursValue is Map
          ? NotificationQuietHours.fromJson(
              Map<String, dynamic>.from(quietHoursValue),
            )
          : null,
    );
  }

  static const defaults = NotificationPreference(level: 'all');
}
