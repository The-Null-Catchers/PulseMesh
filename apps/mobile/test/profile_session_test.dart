import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/profile/profile_session.dart';

void main() {
  test('parses session payload and marks the current session', () {
    final session = ProfileSession.fromJson(
      {
        'id': 'session-1',
        'device': 'PulseMesh Mobile',
        'browser': null,
        'os': 'Android',
        'ip': '203.0.113.5',
        'last_active_at': '2026-10-05T14:00:00.000Z',
        'created_at': '2026-10-01T09:30:00.000Z',
      },
      currentSessionId: 'session-1',
    );

    expect(session.current, isTrue);
    expect(session.title, 'PulseMesh Mobile');
    expect(session.subtitle, 'Android • 203.0.113.5');
    expect(session.lastActiveAt.isUtc, isTrue);
  });

  test('falls back to readable labels when metadata is missing', () {
    final session = ProfileSession.fromJson({
      'id': 'session-2',
      'lastActiveAt': '2026-10-05T14:00:00.000Z',
      'createdAt': '2026-10-05T12:00:00.000Z',
    });

    expect(session.current, isFalse);
    expect(session.title, 'Unknown device');
    expect(session.subtitle, 'Session details unavailable');
  });
}
