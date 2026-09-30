import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/inbox/inbox_controller.dart';
import 'package:pulsemesh/features/inbox/inbox_models.dart';
import 'package:pulsemesh/features/inbox/inbox_transport.dart';

class FakeInboxTransport implements InboxTransport {
  FakeInboxTransport({
    this.failChannelRead = false,
    this.failConversationRead = false,
  });

  final bool failChannelRead;
  final bool failConversationRead;

  @override
  Future<List<ChannelSummary>> channels(String workspaceId) async {
    return [
      ChannelSummary.fromJson({
        'id': 'channel-1',
        'name': 'backend',
        'unread_count': 4,
      }),
    ];
  }

  @override
  Future<List<ConversationSummary>> conversations() async {
    return [
      ConversationSummary.fromJson({
        'id': 'conversation-1',
        'unread_count': 2,
      }),
    ];
  }

  @override
  Future<void> markChannelRead({
    required String channelId,
    required String lastReadMessageId,
  }) async {
    if (failChannelRead) throw StateError('channel read failed');
  }

  @override
  Future<void> markConversationRead({
    required String conversationId,
    required String lastReadMessageId,
  }) async {
    if (failConversationRead) throw StateError('conversation read failed');
  }
}

void main() {
  test('refresh loads channel and conversation unread summaries', () async {
    final controller = InboxController(
      transport: FakeInboxTransport(),
      workspaceId: 'workspace-1',
    );

    final snapshot = await controller.refresh();

    expect(snapshot.totalUnread, 6);
  });

  test('clears channel unread only after read-state succeeds', () async {
    final controller = InboxController(
      transport: FakeInboxTransport(),
      workspaceId: 'workspace-1',
    );
    await controller.refresh();

    await controller.markChannelRead(
      channelId: 'channel-1',
      lastReadMessageId: 'message-1',
    );

    expect(controller.snapshot.channels.single.unreadCount, 0);
  });

  test('keeps channel unread when read-state persistence fails', () async {
    final controller = InboxController(
      transport: FakeInboxTransport(failChannelRead: true),
      workspaceId: 'workspace-1',
    );
    await controller.refresh();

    await expectLater(
      controller.markChannelRead(
        channelId: 'channel-1',
        lastReadMessageId: 'message-1',
      ),
      throwsStateError,
    );

    expect(controller.snapshot.channels.single.unreadCount, 4);
  });

  test('clears conversation unread after read-state succeeds', () async {
    final controller = InboxController(
      transport: FakeInboxTransport(),
      workspaceId: 'workspace-1',
    );
    await controller.refresh();

    await controller.markConversationRead(
      conversationId: 'conversation-1',
      lastReadMessageId: 'message-1',
    );

    expect(controller.snapshot.conversations.single.unreadCount, 0);
  });
}
