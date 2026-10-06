import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/workspaces/workspace_presence.dart';

void main() {
  test('away and dnd statuses are considered connected presence', () {
    for (final status in ['idle', 'do-not-disturb']) {
      final member = WorkspacePresenceMember.fromJson({
        'userId': 'user-$status',
        'status': status,
        'connectedDevices': 1,
      });
      expect(member.isOnline, isTrue);
    }
  });
}
