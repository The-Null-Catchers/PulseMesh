import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/inbox/inbox_models.dart';
import 'package:pulsemesh/features/inbox/inbox_transport.dart';

class FakeGroupInboxTransport implements InboxTransport {
  @override
  Future<List<ChannelSummary>> channels(String workspaceId) async => const [];

  @override
  Future<List<ConversationSummary>> conversations() async => const [];

  @override
  Future<CreatedConversation> createGroupConversation({
    required String name,
    required List<String> memberIds,
  }) async {
    expect(name, 'Product team');
    expect(memberIds, ['user-1', 'user-2']);
    return const CreatedConversation(
      id: 'conversation-1',
      kind: 'group',
      name: 'Product team',
    );
  }

  @override
  Future<void> markChannelRead({
    required String channelId,
    required String lastReadMessageId,
  }) async {}

  @override
  Future<void> markConversationRead({
    required String conversationId,
    required String lastReadMessageId,
  }) async {}
}

void main() {
  test('inbox transport can create a named group conversation', () async {
    final transport = FakeGroupInboxTransport();

    final created = await transport.createGroupConversation(
      name: 'Product team',
      memberIds: ['user-1', 'user-2'],
    );

    expect(created.id, 'conversation-1');
    expect(created.kind, 'group');
    expect(created.name, 'Product team');
  });

  test('created conversation parses API payload', () {
    final created = CreatedConversation.fromJson({
      'id': 'conversation-2',
      'kind': 'group',
      'name': 'Design',
    });

    expect(created.id, 'conversation-2');
    expect(created.kind, 'group');
    expect(created.name, 'Design');
  });
}
