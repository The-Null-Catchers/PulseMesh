import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/messages/saved_message.dart';

void main() {
  test('parses a saved message with a private note', () {
    final saved = SavedMessage.fromJson({
      'messageId': 'message-1',
      'note': 'Follow up tomorrow',
      'createdAt': '2026-10-05T00:00:00.000Z',
      'updatedAt': '2026-10-05T00:01:00.000Z',
      'message': {
        'id': 'message-1',
        'channelId': 'channel-1',
        'conversationId': null,
        'body': 'Deployment is ready.',
        'createdAt': '2026-10-04T23:59:00.000Z',
        'editedAt': null,
        'sender': {
          'id': 'user-1',
          'username': 'mohammed',
          'displayName': 'Mohammed',
          'avatarUrl': null,
        },
      },
    });

    expect(saved.messageId, 'message-1');
    expect(saved.note, 'Follow up tomorrow');
    expect(saved.message.channelId, 'channel-1');
    expect(saved.message.conversationId, isNull);
    expect(saved.message.body, 'Deployment is ready.');
    expect(saved.message.sender.displayName, 'Mohammed');
  });

  test('uses safe defaults for partial saved message payloads', () {
    final saved = SavedMessage.fromJson({
      'messageId': 'message-2',
      'message': <String, dynamic>{},
    });

    expect(saved.messageId, 'message-2');
    expect(saved.note, isNull);
    expect(saved.message.body, isEmpty);
    expect(saved.message.sender.username, isEmpty);
  });
}
