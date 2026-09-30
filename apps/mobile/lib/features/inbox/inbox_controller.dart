import 'inbox_models.dart';
import 'inbox_transport.dart';

class InboxController {
  InboxController({
    required InboxTransport transport,
    required String workspaceId,
  })  : _transport = transport,
        _workspaceId = workspaceId;

  final InboxTransport _transport;
  final String _workspaceId;

  InboxSnapshot _snapshot = const InboxSnapshot(
    channels: [],
    conversations: [],
  );

  InboxSnapshot get snapshot => _snapshot;

  Future<InboxSnapshot> refresh() async {
    final results = await Future.wait([
      _transport.channels(_workspaceId),
      _transport.conversations(),
    ]);

    _snapshot = InboxSnapshot(
      channels: results[0] as List<ChannelSummary>,
      conversations: results[1] as List<ConversationSummary>,
    );
    return _snapshot;
  }

  Future<InboxSnapshot> markChannelRead({
    required String channelId,
    required String lastReadMessageId,
  }) async {
    await _transport.markChannelRead(
      channelId: channelId,
      lastReadMessageId: lastReadMessageId,
    );

    _snapshot = InboxSnapshot(
      channels: _snapshot.channels
          .map(
            (channel) => channel.id == channelId
                ? ChannelSummary(
                    id: channel.id,
                    name: channel.name,
                    unreadCount: 0,
                    visibility: channel.visibility,
                    position: channel.position,
                  )
                : channel,
          )
          .toList(growable: false),
      conversations: _snapshot.conversations,
    );
    return _snapshot;
  }

  Future<InboxSnapshot> markConversationRead({
    required String conversationId,
    required String lastReadMessageId,
  }) async {
    await _transport.markConversationRead(
      conversationId: conversationId,
      lastReadMessageId: lastReadMessageId,
    );

    _snapshot = InboxSnapshot(
      channels: _snapshot.channels,
      conversations: _snapshot.conversations
          .map(
            (conversation) => conversation.id == conversationId
                ? ConversationSummary(
                    id: conversation.id,
                    kind: conversation.kind,
                    name: conversation.name,
                    avatarUrl: conversation.avatarUrl,
                    encryptionMode: conversation.encryptionMode,
                    unreadCount: 0,
                    members: conversation.members,
                  )
                : conversation,
          )
          .toList(growable: false),
    );
    return _snapshot;
  }
}
