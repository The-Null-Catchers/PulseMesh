import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/inbox/inbox_models.dart';

void main() {
  group('inbox models', () {
    test('parses unread channel summaries', () {
      final channel = ChannelSummary.fromJson({
        'id': 'channel-1',
        'name': 'backend',
        'visibility': 'public',
        'position': 2,
        'unread_count': 6,
      });

      expect(channel.id, 'channel-1');
      expect(channel.name, 'backend');
      expect(channel.unreadCount, 6);
      expect(channel.hasUnread, isTrue);
    });

    test('parses conversation members and unread counts', () {
      final conversation = ConversationSummary.fromJson({
        'id': 'conversation-1',
        'kind': 'direct',
        'name': null,
        'avatar_url': null,
        'encryption_mode': 'e2ee_v1',
        'unread_count': '3',
        'members': [
          {
            'id': 'user-1',
            'username': 'lama',
            'displayName': 'Lama',
            'avatarUrl': null,
          },
        ],
      });

      expect(conversation.encryptionMode, 'e2ee_v1');
      expect(conversation.unreadCount, 3);
      expect(conversation.members.single.displayName, 'Lama');
    });

    test('totals unread across channels and conversations', () {
      final snapshot = InboxSnapshot(
        channels: [
          ChannelSummary.fromJson({
            'id': 'channel-1',
            'name': 'general',
            'unread_count': 2,
          }),
          ChannelSummary.fromJson({
            'id': 'channel-2',
            'name': 'backend',
            'unread_count': 4,
          }),
        ],
        conversations: [
          ConversationSummary.fromJson({
            'id': 'conversation-1',
            'unread_count': 3,
          }),
        ],
      );

      expect(snapshot.totalUnread, 9);
    });
  });
}
