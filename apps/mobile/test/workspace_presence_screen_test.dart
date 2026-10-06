import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/workspaces/workspace_presence.dart';

void main() {
  test('offline workspace presence retains last seen timestamp', () {
    final member = WorkspacePresenceMember.fromJson({
      'userId': 'user-2',
      'username': 'nora',
      'displayName': 'Nora',
      'status': 'offline',
      'lastSeenAt': '2026-10-06T14:00:00Z',
      'connectedDevices': 0,
    });

    expect(member.isOnline, isFalse);
    expect(member.lastSeenAt, DateTime.parse('2026-10-06T14:00:00Z'));
  });
}
