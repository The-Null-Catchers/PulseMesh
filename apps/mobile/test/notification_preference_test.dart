import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/profile/notification_preference.dart';

void main() {
  test('parses global notification preference quiet hours', () {
    final preference = NotificationPreference.fromJson({
      'level': 'mentions',
      'quiet_hours': {
        'start': '22:30',
        'end': '07:15',
        'timezone': 'Asia/Gaza',
      },
    });

    expect(preference.level, 'mentions');
    expect(preference.quietHours, isNotNull);
    expect(preference.quietHours!.start, '22:30');
    expect(preference.quietHours!.end, '07:15');
    expect(preference.quietHours!.timezone, 'Asia/Gaza');
  });

  test('notification preference defaults are safe', () {
    final preference = NotificationPreference.fromJson(const {});

    expect(preference.level, 'all');
    expect(preference.quietHours, isNull);
    expect(NotificationPreference.defaults.level, 'all');
  });
}
