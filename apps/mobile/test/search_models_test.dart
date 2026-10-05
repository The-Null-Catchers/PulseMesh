import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh_mobile/features/search/search_models.dart';

void main() {
  test('parses global search results', () {
    final results = SearchResults.fromJson({
      'messages': [
        {
          'id': 'message-1',
          'body': 'hello PulseMesh',
          'channel_id': 'channel-1',
          'conversation_id': null,
          'created_at': '2026-10-05T04:00:00.000Z',
          'username': 'mohammed',
          'display_name': 'Mohammed',
        },
      ],
      'users': [
        {
          'id': 'user-1',
          'username': 'lama',
          'display_name': 'Lama',
          'avatar_url': null,
        },
      ],
      'channels': [
        {
          'id': 'channel-1',
          'name': 'general',
          'workspace_id': 'workspace-1',
        },
      ],
    });

    expect(results.messages, hasLength(1));
    expect(results.messages.single.channelId, 'channel-1');
    expect(results.messages.single.displayName, 'Mohammed');
    expect(results.users.single.username, 'lama');
    expect(results.channels.single.name, 'general');
    expect(results.isEmpty, isFalse);
  });

  test('empty global search payload is safe', () {
    final results = SearchResults.fromJson(const {});

    expect(results.messages, isEmpty);
    expect(results.users, isEmpty);
    expect(results.channels, isEmpty);
    expect(results.isEmpty, isTrue);
  });
}
