import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/profile/profile_model.dart';

void main() {
  test('parses authenticated profile payload', () {
    final profile = UserProfile.fromJson({
      'id': 'user-1',
      'email': 'user@example.com',
      'username': 'mohammed',
      'displayName': 'Mohammed',
      'avatarUrl': 'https://example.com/avatar.png',
      'bio': 'Building PulseMesh',
      'timezone': 'Asia/Hebron',
      'statusText': 'Shipping realtime features',
      'createdAt': '2026-10-01T12:00:00.000Z',
      'updatedAt': '2026-10-05T12:00:00.000Z',
    });

    expect(profile.username, 'mohammed');
    expect(profile.displayName, 'Mohammed');
    expect(profile.timezone, 'Asia/Hebron');
    expect(profile.bio, 'Building PulseMesh');
    expect(profile.createdAt.isUtc, isTrue);
  });

  test('profile parser falls back safely for optional fields', () {
    final profile = UserProfile.fromJson(const {
      'id': 'user-2',
      'email': 'two@example.com',
      'username': 'two',
      'displayName': 'Two',
    });

    expect(profile.avatarUrl, isNull);
    expect(profile.bio, isNull);
    expect(profile.statusText, isNull);
    expect(profile.timezone, 'UTC');
  });
}
