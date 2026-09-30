import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/inbox/inbox_realtime.dart';

void main() {
  test('parses inbox message signals without message content', () {
    final signal = InboxMessageSignal.fromRealtime({
      'type': 'inbox.message',
      'payload': {
        'messageId': 'message-1',
        'workspaceId': 'workspace-1',
        'channelId': 'channel-1',
        'conversationId': null,
        'senderId': 'user-1',
        'createdAt': '2026-09-30T10:00:00.000Z',
      },
    });

    expect(signal.messageId, 'message-1');
    expect(signal.workspaceId, 'workspace-1');
    expect(signal.channelId, 'channel-1');
    expect(signal.conversationId, isNull);
    expect(signal.createdAt.isUtc, isTrue);
  });

  test('rejects non-inbox events', () {
    expect(
      () => InboxMessageSignal.fromRealtime({
        'type': 'message.created',
        'payload': <String, dynamic>{},
      }),
      throwsFormatException,
    );
  });

  test('advances realtime sequence monotonically', () {
    expect(advanceRealtimeSequence(10, 12), 12);
    expect(advanceRealtimeSequence(12, 11), 12);
    expect(advanceRealtimeSequence(12, null), 12);
  });
}
