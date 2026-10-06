import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/workspaces/workspace_presence.dart';

void main() {
  test('parses workspace presence member and merges realtime snapshot', () {
    final member = WorkspacePresenceMember.fromJson({
      'userId': 'u1',
      'username': 'sam',
      'displayName': 'Sam',
      'avatarUrl': null,
      'status': 'online',
      'customText': 'Focus',
      'lastSeenAt': '2026-10-06T12:00:00Z',
      'connectedDevices': 1,
      'activeWorkspaceId': 'w1',
    });

    final updated = member.mergeSnapshot({
      'userId': 'u1',
      'status': 'do-not-disturb',
      'customText': 'Deep work',
      'connectedDevices': 2,
      'activeWorkspaceId': 'w1',
    });

    expect(updated.username, 'sam');
    expect(updated.displayName, 'Sam');
    expect(updated.status, 'do-not-disturb');
    expect(updated.customText, 'Deep work');
    expect(updated.connectedDevices, 2);
  });

  test('defaults sparse member safely to offline', () {
    final member = WorkspacePresenceMember.fromJson(const {});

    expect(member.status, 'offline');
    expect(member.connectedDevices, 0);
    expect(member.isOnline, isFalse);
  });
}
