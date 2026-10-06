import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/workspaces/workspace_presence.dart';

void main() {
  test('keeps workspace member identity on a realtime merge', () {
    final member = WorkspacePresenceMember.fromJson({
      'userId': 'user-1',
      'username': 'mohammed',
      'displayName': 'Mohammed',
      'status': 'offline',
      'connectedDevices': 0,
    });

    final merged = member.mergeSnapshot({
      'userId': 'user-1',
      'status': 'online',
      'customText': 'Available',
      'connectedDevices': 1,
    });

    expect(merged.userId, 'user-1');
    expect(merged.username, 'mohammed');
    expect(merged.displayName, 'Mohammed');
    expect(merged.status, 'online');
    expect(merged.customText, 'Available');
    expect(merged.connectedDevices, 1);
  });
}
