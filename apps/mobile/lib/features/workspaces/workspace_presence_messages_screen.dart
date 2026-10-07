import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../inbox/create_group_conversation_screen.dart';
import '../inbox/inbox_models.dart';
import '../inbox/inbox_realtime.dart';
import '../inbox/inbox_transport.dart';
import '../inbox/mobile_data_controller.dart';
import '../inbox/mobile_data_scope.dart';
import '../messages/message_actions_transport.dart';
import '../messages/room_screen.dart';
import '../messages/saved_messages_screen.dart';
import 'workspace_presence.dart';
import 'workspace_transport.dart';

class WorkspacePresenceMessagesScreen extends StatefulWidget {
  const WorkspacePresenceMessagesScreen({super.key});

  @override
  State<WorkspacePresenceMessagesScreen> createState() =>
      _WorkspacePresenceMessagesScreenState();
}

class _WorkspacePresenceMessagesScreenState
    extends State<WorkspacePresenceMessagesScreen> {
  Map<String, WorkspacePresenceMember> _presence = const {};
  StreamSubscription<Map<String, dynamic>>? _events;
  MobileDataController? _data;
  WorkspaceTransport? _transport;
  String? _loadedWorkspaceId;
  Object? _presenceError;
  bool _loadingPresence = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = MobileDataScope.of(context);
    if (!identical(_data, data)) {
      _events?.cancel();
      _data = data;
      _events = data.realtimeEvents.listen(_handleRealtimeEvent);
    }

    final actions = SavedMessagesTransportScope.of(context);
    if (actions is DioMessageActionsTransport) {
      _transport ??= DioWorkspaceTransport(
        baseUrl: actions.baseUrl,
        accessToken: actions.accessTokenProvider,
      );
    }

    final workspaceId = data.selectedWorkspaceId;
    if (workspaceId != null && workspaceId != _loadedWorkspaceId) {
      _loadedWorkspaceId = workspaceId;
      unawaited(_loadPresence(workspaceId));
    }
  }

  Future<void> _loadPresence(String workspaceId) async {
    final transport = _transport;
    if (transport == null) return;

    setState(() {
      _loadingPresence = true;
      _presenceError = null;
    });
    try {
      final members = await transport.listPresence(workspaceId);
      if (!mounted || _data?.selectedWorkspaceId != workspaceId) return;
      setState(() {
        _presence = {
          for (final member in members) member.userId: member,
        };
        _presenceError = null;
      });
    } catch (error) {
      if (!mounted || _data?.selectedWorkspaceId != workspaceId) return;
      setState(() => _presenceError = error);
    } finally {
      if (mounted && _data?.selectedWorkspaceId == workspaceId) {
        setState(() => _loadingPresence = false);
      }
    }
  }

  void _handleRealtimeEvent(Map<String, dynamic> event) {
    if (event['type'] != 'presence.updated') return;
    final payloadValue = event['payload'];
    if (payloadValue is! Map) return;
    final payload = Map<String, dynamic>.from(payloadValue);
    final userId = payload['userId'] as String?;
    if (userId == null || userId.isEmpty) return;

    final existing = _presence[userId];
    if (existing == null || !mounted) return;
    setState(() {
      _presence = {
        ..._presence,
        userId: existing.mergeSnapshot(payload),
      };
    });
  }

  Future<void> _refresh() async {
    final data = _data;
    if (data == null) return;
    await data.refresh();
    final workspaceId = data.selectedWorkspaceId;
    if (workspaceId != null) {
      _loadedWorkspaceId = workspaceId;
      await _loadPresence(workspaceId);
    }
  }

  Future<void> _openCreateGroup() async {
    final data = _data;
    final workspaceId = data?.selectedWorkspaceId;
    final workspaceTransport = _transport;
    final actions = SavedMessagesTransportScope.of(context);

    if (data == null || workspaceId == null || workspaceTransport == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a workspace first.')),
      );
      return;
    }
    if (actions is! DioMessageActionsTransport) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group creation is unavailable.')),
      );
      return;
    }

    final created = await Navigator.of(context).push<CreatedConversation>(
      MaterialPageRoute(
        builder: (_) => CreateGroupConversationScreen(
          workspaceId: workspaceId,
          currentUserId: data.currentUserId,
          workspaceTransport: workspaceTransport,
          inboxTransport: DioInboxTransport(
            baseUrl: actions.baseUrl,
            accessToken: actions.accessTokenProvider,
          ),
        ),
      ),
    );
    if (!mounted || created == null || created.id.isEmpty) return;

    await data.refresh();
    if (!mounted) return;
    final title = created.name?.trim().isNotEmpty == true
        ? created.name!.trim()
        : 'Group conversation';
    context.push(
      '/room/conversation/${created.id}',
      extra: RoomScreenArgs(title: title, encrypted: false),
    );
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = MobileDataScope.of(context);
    final conversations = data.inbox.conversations;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: const Color(0xFF071015),
            title: const Text(
              'Messages',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
              if (_loadingPresence)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'New group',
                onPressed: _openCreateGroup,
                icon: const Icon(Icons.group_add_outlined),
              ),
              IconButton(
                tooltip: 'Search PulseMesh',
                onPressed: () => context.push('/search'),
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'Saved messages',
                onPressed: () => context.push('/saved'),
                icon: const Icon(Icons.bookmark_outline_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
          if (data.offline || data.realtimeState != MobileRealtimeState.ready)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _ConnectionBanner(data: data),
              ),
            ),
          if (_presenceError != null)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _PresenceUnavailableBanner(),
              ),
            ),
          if (conversations.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: _EmptyMessagesState(),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              sliver: SliverList.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  final peer = _directPeer(conversation, data.currentUserId);
                  return _PresenceConversationTile(
                    conversation: conversation,
                    presence: peer == null ? null : _presence[peer.id],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PresenceConversationTile extends StatelessWidget {
  const _PresenceConversationTile({
    required this.conversation,
    required this.presence,
  });

  final ConversationSummary conversation;
  final WorkspacePresenceMember? presence;

  @override
  Widget build(BuildContext context) {
    final title = _conversationTitle(conversation);
    final encrypted = conversation.encryptionMode != 'none';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tileColor: conversation.hasUnread
            ? const Color(0x1468E0CF)
            : Colors.transparent,
        leading: _PresenceAvatar(title: title, presence: presence),
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: conversation.hasUnread
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            if (encrypted) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.lock_outline_rounded,
                size: 15,
                color: Color(0xFF68E0CF),
              ),
            ],
          ],
        ),
        subtitle: Text(
          conversation.kind == 'group'
              ? 'Group conversation'
              : _presenceSubtitle(presence),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: conversation.hasUnread
            ? Badge(
                label: Text(
                  conversation.unreadCount > 99
                      ? '99+'
                      : '${conversation.unreadCount}',
                ),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: () {
          context.push(
            '/room/conversation/${conversation.id}',
            extra: RoomScreenArgs(
              title: title,
              encrypted: encrypted,
            ),
          );
        },
      ),
    );
  }
}

class _PresenceAvatar extends StatelessWidget {
  const _PresenceAvatar({required this.title, required this.presence});

  final String title;
  final WorkspacePresenceMember? presence;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          backgroundColor: const Color(0xFF153039),
          child: Text(title.isEmpty ? '?' : title.characters.first.toUpperCase()),
        ),
        if (presence != null)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: _presenceColor(presence!.status),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF071015), width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.data});

  final MobileDataController data;

  @override
  Widget build(BuildContext context) {
    final offline = data.offline;
    final label = switch (data.realtimeState) {
      MobileRealtimeState.ready => 'connected',
      MobileRealtimeState.connecting => 'connecting',
      MobileRealtimeState.reconnecting => 'reconnecting',
      MobileRealtimeState.disconnected => 'disconnected',
    };
    final message = offline
        ? 'Offline • showing cached workspace data'
        : 'Realtime connection is $label';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF102128),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF24404A)),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_rounded : Icons.sync_rounded,
            size: 18,
            color: offline ? Colors.orangeAccent : const Color(0xFF68E0CF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresenceUnavailableBanner extends StatelessWidget {
  const _PresenceUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF211B12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.people_outline_rounded, size: 18, color: Colors.amber),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Live presence is unavailable • pull to retry',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessagesState extends StatelessWidget {
  const _EmptyMessagesState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.forum_outlined, color: Colors.white38),
        SizedBox(height: 8),
        Text(
          'No direct or group conversations yet.',
          style: TextStyle(color: Colors.white54),
        ),
      ],
    );
  }
}

ConversationMemberSummary? _directPeer(
  ConversationSummary conversation,
  String? currentUserId,
) {
  if (conversation.kind != 'direct') return null;
  for (final member in conversation.members) {
    if (member.id != currentUserId) return member;
  }
  return null;
}

String _conversationTitle(ConversationSummary conversation) {
  final customName = conversation.name?.trim();
  if (customName != null && customName.isNotEmpty) return customName;

  final names = conversation.members
      .map((member) {
        final displayName = member.displayName.trim();
        if (displayName.isNotEmpty) return displayName;
        return member.username.trim();
      })
      .where((name) => name.isNotEmpty)
      .take(3)
      .toList(growable: false);

  if (names.isNotEmpty) return names.join(', ');
  return conversation.kind == 'group' ? 'Group conversation' : 'Direct message';
}

String _presenceSubtitle(WorkspacePresenceMember? presence) {
  if (presence == null) return 'Direct message';
  final customText = presence.customText?.trim();
  if (customText != null && customText.isNotEmpty) return customText;

  return switch (presence.status) {
    'online' => 'Online',
    'idle' => 'Away',
    'do-not-disturb' => 'Do not disturb',
    _ => presence.lastSeenAt == null
        ? 'Offline'
        : 'Last seen ${_formatLastSeen(presence.lastSeenAt!)}',
  };
}

Color _presenceColor(String status) {
  return switch (status) {
    'online' => const Color(0xFF68E0CF),
    'idle' => Colors.amberAccent,
    'do-not-disturb' => Colors.redAccent,
    _ => Colors.blueGrey,
  };
}

String _formatLastSeen(DateTime value) {
  final local = value.toLocal();
  final difference = DateTime.now().difference(local);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
