import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../inbox/create_group_conversation_screen.dart';
import '../inbox/group_details_screen.dart';
import '../inbox/group_management_transport.dart';
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
  WorkspaceTransport? _workspaceTransport;
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
      _workspaceTransport ??= DioWorkspaceTransport(
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
    final transport = _workspaceTransport;
    if (transport == null) return;
    setState(() {
      _loadingPresence = true;
      _presenceError = null;
    });
    try {
      final members = await transport.listPresence(workspaceId);
      if (!mounted || _data?.selectedWorkspaceId != workspaceId) return;
      setState(() {
        _presence = {for (final member in members) member.userId: member};
      });
    } catch (error) {
      if (mounted) setState(() => _presenceError = error);
    } finally {
      if (mounted) setState(() => _loadingPresence = false);
    }
  }

  void _handleRealtimeEvent(Map<String, dynamic> event) {
    if (event['type'] != 'presence.updated') return;
    final raw = event['payload'];
    if (raw is! Map) return;
    final payload = Map<String, dynamic>.from(raw);
    final userId = payload['userId'] as String?;
    final existing = userId == null ? null : _presence[userId];
    if (existing == null || !mounted) return;
    setState(() {
      _presence = {..._presence, userId!: existing.mergeSnapshot(payload)};
    });
  }

  Future<void> _refresh() async {
    final data = _data;
    if (data == null) return;
    await data.refresh();
    final workspaceId = data.selectedWorkspaceId;
    if (workspaceId != null) await _loadPresence(workspaceId);
  }

  Future<void> _openCreateGroup() async {
    final data = _data;
    final workspaceId = data?.selectedWorkspaceId;
    final workspaceTransport = _workspaceTransport;
    final actions = SavedMessagesTransportScope.of(context);
    if (data == null || workspaceId == null || workspaceTransport == null ||
        actions is! DioMessageActionsTransport) {
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
    context.push(
      '/room/conversation/${created.id}',
      extra: RoomScreenArgs(
        title: created.name?.trim().isNotEmpty == true
            ? created.name!.trim()
            : 'Group conversation',
      ),
    );
  }

  Future<void> _openGroupDetails(ConversationSummary conversation) async {
    final data = _data;
    final workspaceId = data?.selectedWorkspaceId;
    final workspaceTransport = _workspaceTransport;
    final actions = SavedMessagesTransportScope.of(context);
    if (data == null || workspaceId == null || workspaceTransport == null ||
        actions is! DioMessageActionsTransport) {
      return;
    }

    final leftGroup = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GroupDetailsScreen(
          conversation: conversation,
          currentUserId: data.currentUserId,
          workspaceId: workspaceId,
          workspaceTransport: workspaceTransport,
          groupTransport: DioGroupManagementTransport(
            baseUrl: actions.baseUrl,
            accessToken: actions.accessTokenProvider,
          ),
        ),
      ),
    );
    if (!mounted) return;
    await data.refresh();
    if (leftGroup == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left the group.')),
      );
    }
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
            title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.w800)),
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
            ],
          ),
          if (data.offline || data.realtimeState != MobileRealtimeState.ready)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _Banner(
                  icon: data.offline ? Icons.cloud_off_rounded : Icons.sync_rounded,
                  text: data.offline
                      ? 'Offline • showing cached workspace data'
                      : 'Realtime connection is ${data.realtimeState.name}',
                ),
              ),
            ),
          if (_presenceError != null)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _Banner(
                  icon: Icons.people_outline_rounded,
                  text: 'Live presence is unavailable • pull to retry',
                ),
              ),
            ),
          if (conversations.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No direct or group conversations yet.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              sliver: SliverList.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  final peer = _directPeer(conversation, data.currentUserId);
                  return _ConversationTile(
                    conversation: conversation,
                    presence: peer == null ? null : _presence[peer.id],
                    onManage: conversation.kind == 'group'
                        ? () => _openGroupDetails(conversation)
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.presence,
    this.onManage,
  });

  final ConversationSummary conversation;
  final WorkspacePresenceMember? presence;
  final VoidCallback? onManage;

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
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF153039),
          child: Text(title.isEmpty ? '?' : title.characters.first.toUpperCase()),
        ),
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: conversation.hasUnread ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          conversation.kind == 'group'
              ? '${conversation.members.length} members'
              : _presenceSubtitle(presence),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conversation.hasUnread)
              Badge(
                label: Text(
                  conversation.unreadCount > 99 ? '99+' : '${conversation.unreadCount}',
                ),
              ),
            if (onManage != null)
              IconButton(
                tooltip: 'Group details',
                onPressed: onManage,
                icon: const Icon(Icons.more_vert_rounded),
              )
            else
              const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: () {
          context.push(
            '/room/conversation/${conversation.id}',
            extra: RoomScreenArgs(title: title, encrypted: encrypted),
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF102128),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
        ],
      ),
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
      .map((member) => member.displayName.trim().isNotEmpty
          ? member.displayName.trim()
          : member.username.trim())
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
    _ => 'Offline',
  };
}
