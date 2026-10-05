import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/profile/presence_snapshot.dart';

void main() {
  test('parses an online presence snapshot', () {
    final snapshot = PresenceSnapshot.fromJson({
      'userId': 'user-1',
      'status': 'do-not-disturb',
      'customText': 'Deep work',
      'lastSeenAt': '2026-10-05T20:00:00.000Z',
      'connectedDevices': 2,
      'activeWorkspaceId': 'workspace-1',
    });

    expect(snapshot.userId, 'user-1');
    expect(snapshot.status, 'do-not-disturb');
    expect(snapshot.customText, 'Deep work');
    expect(snapshot.connectedDevices, 2);
    expect(snapshot.activeWorkspaceId, 'workspace-1');
    expect(snapshot.isOnline, isTrue);
  });

  test('defaults a sparse presence payload to offline', () {
    final snapshot = PresenceSnapshot.fromJson(const {});

    expect(snapshot.status, 'offline');
    expect(snapshot.connectedDevices, 0);
    expect(snapshot.isOnline, isFalse);
  });
}
