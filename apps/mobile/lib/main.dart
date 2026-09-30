import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth/auth_bootstrap.dart';
import 'auth/auth_session_controller.dart';
import 'config/app_config.dart';
import 'features/inbox/inbox_models.dart';
import 'features/inbox/inbox_realtime.dart';
import 'features/inbox/mobile_data_controller.dart';
import 'features/inbox/mobile_data_scope.dart';
import 'features/messages/room_screen.dart';
import 'offline/models.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      child: MobileAuthBootstrap(
        authenticatedAppBuilder: (authSession) => PulseMeshAuthenticatedRoot(
          authSession: authSession,
          config: AppConfig.fromEnvironment,
        ),
      ),
    ),
  );
}

class PulseMeshAuthenticatedRoot extends StatefulWidget {
  const PulseMeshAuthenticatedRoot({
    required this.authSession,
    required this.config,
    super.key,
  });

  final AuthSessionController authSession;
  final AppConfig config;

  @override
  State<PulseMeshAuthenticatedRoot> createState() =>
      _PulseMeshAuthenticatedRootState();
}

class _PulseMeshAuthenticatedRootState
    extends State<PulseMeshAuthenticatedRoot> {
  late final MobileDataController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileDataController.live(
      authSession: widget.authSession,
      config: widget.config,
    );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileDataScope(
      controller: _controller,
      child: const PulseMeshApp(),
    );
  }
}

final router = GoRouter(
  initialLocation: '/home',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/messages', builder: (_, _) => const MessagesScreen()),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const PlaceholderScreen(title: 'Activity'),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) => const PlaceholderScreen(title: 'Profile'),
        ),
      ],
    ),
    GoRoute(
      path: '/room/:kind/:id',
      builder: (context, state) {
        final kind = state.pathParameters['kind'];
        final id = state.pathParameters['id']!;
        final roomKind =
            kind == 'channel' ? RoomKind.channel : RoomKind.conversation;
        final args = state.extra is RoomScreenArgs
            ? state.extra! as RoomScreenArgs
            : const RoomScreenArgs(title: 'Conversation');

        return RoomScreen(
          room: RoomRef(kind: roomKind, id: id),
          title: args.title,
          encrypted: args.encrypted,
        );
      },
    ),
  ],
);

class PulseMeshApp extends StatelessWidget {
  const PulseMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'PulseMesh',
      theme: buildPulseMeshTheme(),
      routerConfig: router,
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  int indexFor(String location) {
    if (location.startsWith('/messages')) return 1;
    if (location.startsWith('/activity')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final data = MobileDataScope.of(context);

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: indexFor(location),
        onDestinationSelected: (index) {
          const paths = ['/home', '/messages', '/activity', '/profile'];
          context.go(paths[index]);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: _UnreadNavigationIcon(
              count: data.totalUnread,
              icon: Icons.chat_bubble_outline_rounded,
            ),
            selectedIcon: _UnreadNavigationIcon(
              count: data.totalUnread,
              icon: Icons.chat_bubble_rounded,
            ),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.notifications_none_rounded),
            label: 'Activity',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _UnreadNavigationIcon extends StatelessWidget {
  const _UnreadNavigationIcon({
    required this.count,
    required this.icon,
  });

  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final base = Icon(icon);
    if (count <= 0) return base;

    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      child: base,
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MobileDataScope.of(context);
    final workspace = data.selectedWorkspace;
    final textChannels =
        data.inbox.channels.where((channel) => !channel.isVoice).toList();
    final voiceChannels =
        data.inbox.channels.where((channel) => channel.isVoice).toList();

    if (data.loading &&
        data.workspaces.isEmpty &&
        data.inbox.conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: data.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: const Color(0xFF071015),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workspace?.name ?? 'PulseMesh',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  workspace == null
                      ? 'Choose or create a workspace'
                      : '${workspace.role} • @${workspace.slug}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            actions: [
              if (data.workspaces.length > 1)
                PopupMenuButton<String>(
                  tooltip: 'Switch workspace',
                  initialValue: data.selectedWorkspaceId,
                  onSelected: (workspaceId) {
                    unawaited(data.selectWorkspace(workspaceId));
                  },
                  itemBuilder: (context) => data.workspaces
                      .map(
                        (item) => PopupMenuItem(
                          value: item.id,
                          child: Row(
                            children: [
                              _WorkspaceAvatar(name: item.name, size: 30),
                              const SizedBox(width: 10),
                              Expanded(child: Text(item.name)),
                              if (item.id == data.selectedWorkspaceId)
                                const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Color(0xFF68E0CF),
                                ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                  icon: const Icon(Icons.swap_vert_rounded),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _WorkspaceAvatar(
                  name: workspace?.name ?? 'PulseMesh',
                  size: 36,
                ),
              ),
            ],
          ),
          if (data.offline ||
              data.realtimeState != MobileRealtimeState.ready)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _ConnectionBanner(data: data),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _WorkspaceOverviewCard(data: data),
            ),
          ),
          if (workspace == null)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 24),
              sliver: SliverToBoxAdapter(
                child: _NoWorkspaceState(),
              ),
            )
          else ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
              sliver: SliverToBoxAdapter(
                child: _SectionTitle(title: 'Channels'),
              ),
            ),
            if (textChannels.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverToBoxAdapter(
                  child: _EmptySection(
                    icon: Icons.tag_rounded,
                    message: 'No text channels yet.',
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: textChannels.length,
                itemBuilder: (context, index) {
                  final channel = textChannels[index];
                  return _ChannelTile(channel: channel);
                },
              ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(18, 22, 18, 8),
              sliver: SliverToBoxAdapter(
                child: _SectionTitle(title: 'Voice'),
              ),
            ),
            if (voiceChannels.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverToBoxAdapter(
                  child: _EmptySection(
                    icon: Icons.graphic_eq_rounded,
                    message: 'No voice rooms yet.',
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: voiceChannels.length,
                itemBuilder: (context, index) {
                  final channel = voiceChannels[index];
                  return _VoiceChannelTile(channel: channel);
                },
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MobileDataScope.of(context);
    final conversations = data.inbox.conversations;

    return RefreshIndicator(
      onRefresh: data.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverAppBar(
            floating: true,
            backgroundColor: Color(0xFF071015),
            title: Text(
              'Messages',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (data.offline ||
              data.realtimeState != MobileRealtimeState.ready)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _ConnectionBanner(data: data),
              ),
            ),
          if (conversations.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: _EmptySection(
                  icon: Icons.forum_outlined,
                  message: 'No direct or group conversations yet.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              sliver: SliverList.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  return _ConversationTile(
                    conversation: conversations[index],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceOverviewCard extends StatelessWidget {
  const _WorkspaceOverviewCard({required this.data});

  final MobileDataController data;

  @override
  Widget build(BuildContext context) {
    final unread = data.totalUnread;
    final copy = unread == 0
        ? 'You are caught up across channels and conversations.'
        : '$unread unread ${unread == 1 ? 'message' : 'messages'} need your attention.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF12312F), Color(0xFF112638)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x3368E0CF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Color(0xFF68E0CF)),
              const SizedBox(width: 8),
              Text(
                _realtimeLabel(data.realtimeState),
                style: const TextStyle(color: Color(0xFF9AF5E8)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            data.selectedWorkspace?.name ?? 'Your PulseMesh space',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            copy,
            style: const TextStyle(
              color: Colors.white60,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.data});

  final MobileDataController data;

  @override
  Widget build(BuildContext context) {
    final offline = data.offline;
    final message = offline
        ? 'Offline • showing cached workspace data'
        : 'Realtime connection is ${_realtimeLabel(data.realtimeState).toLowerCase()}';

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
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel});

  final ChannelSummary channel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        tileColor:
            channel.hasUnread ? const Color(0x1468E0CF) : Colors.transparent,
        leading: const Icon(Icons.tag_rounded),
        title: Text(
          channel.name,
          style: TextStyle(
            fontWeight: channel.hasUnread ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: channel.visibility == 'public'
            ? null
            : Text(channel.visibility),
        trailing: channel.hasUnread
            ? Badge(
                label: Text(
                  channel.unreadCount > 99
                      ? '99+'
                      : '${channel.unreadCount}',
                ),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: () {
          context.push(
            '/room/channel/${channel.id}',
            extra: RoomScreenArgs(title: '#${channel.name}'),
          );
        },
      ),
    );
  }
}

class _VoiceChannelTile extends StatelessWidget {
  const _VoiceChannelTile({required this.channel});

  final ChannelSummary channel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        leading: const Icon(
          Icons.graphic_eq_rounded,
          color: Color(0xFF68E0CF),
        ),
        title: Text(channel.name),
        subtitle: Text(channel.visibility),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final title = _conversationTitle(conversation);
    final encrypted = conversation.encryptionMode != 'none';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        tileColor: conversation.hasUnread
            ? const Color(0x1468E0CF)
            : Colors.transparent,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF153039),
          child: Text(
            title.isEmpty ? '?' : title.characters.first.toUpperCase(),
          ),
        ),
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
              : 'Direct message',
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
              encrypted: conversation.encryptionMode != 'none',
            ),
          );
        },
      ),
    );
  }
}

class _WorkspaceAvatar extends StatelessWidget {
  const _WorkspaceAvatar({
    required this.name,
    required this.size,
  });

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? 'P' : name.trim().characters.first;

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF153039),
      child: Text(
        letter.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.white54,
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white38),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _NoWorkspaceState extends StatelessWidget {
  const _NoWorkspaceState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0B171C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF24404A)),
      ),
      child: const Column(
        children: [
          Icon(Icons.hub_outlined, size: 36, color: Color(0xFF68E0CF)),
          SizedBox(height: 12),
          Text(
            'No workspace yet',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Create or join a workspace on PulseMesh to start seeing channels here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
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

String _realtimeLabel(MobileRealtimeState state) {
  return switch (state) {
    MobileRealtimeState.ready => 'Realtime connected',
    MobileRealtimeState.connecting => 'Connecting',
    MobileRealtimeState.reconnecting => 'Reconnecting',
    MobileRealtimeState.disconnected => 'Disconnected',
  };
}
