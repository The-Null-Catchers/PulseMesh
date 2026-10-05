import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth/auth_bootstrap.dart';
import 'auth/auth_session_controller.dart';
import 'config/app_config.dart';
import 'features/calls/call_activity_badge.dart';
import 'features/calls/call_activity_screen.dart';
import 'features/calls/call_transport.dart';
import 'features/calls/video_call_screen.dart';
import 'features/calls/voice_room_screen.dart';
import 'features/inbox/inbox_models.dart';
import 'features/inbox/inbox_realtime.dart';
import 'features/inbox/mobile_data_controller.dart';
import 'features/inbox/mobile_data_scope.dart';
import 'features/messages/message_actions_transport.dart';
import 'features/messages/room_screen.dart';
import 'features/messages/saved_messages_screen.dart';
import 'features/notifications/call_notification_action.dart';
import 'features/notifications/mobile_push_service.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/profile_transport.dart';
import 'features/search/search_screen.dart';
import 'features/search/search_transport.dart';
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
  late final CallTransport _callTransport;
  late final MessageActionsTransport _messageActionsTransport;

  @override
  void initState() {
    super.initState();
    _controller = MobileDataController.live(
      authSession: widget.authSession,
      config: widget.config,
    );
    _callTransport = DioCallTransport(
      baseUrl: widget.config.apiBaseUrl,
      accessToken: widget.authSession.accessToken,
    );
    _messageActionsTransport = DioMessageActionsTransport(
      baseUrl: widget.config.apiBaseUrl,
      accessToken: widget.authSession.accessToken,
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
    return SavedMessagesTransportScope(
      transport: _messageActionsTransport,
      child: MobileDataScope(
        controller: _controller,
        child: PulseMeshApp(callTransport: _callTransport),
      ),
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
          builder: (_, _) => const CallActivityScreen(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, _) {
            final actions = SavedMessagesTransportScope.of(context);
            if (actions is! DioMessageActionsTransport) {
              return const PlaceholderScreen(title: 'Profile unavailable');
            }
            return ProfileScreen(
              transport: DioProfileTransport(
                baseUrl: actions.baseUrl,
                accessToken: actions.accessTokenProvider,
              ),
            );
          },
        ),
      ],
    ),
    GoRoute(path: '/saved', builder: (_, _) => const SavedMessagesScreen()),
    GoRoute(
      path: '/search',
      builder: (context, _) {
        final actions = SavedMessagesTransportScope.of(context);
        if (actions is! DioMessageActionsTransport) {
          return const PlaceholderScreen(title: 'Search unavailable');
        }
        return SearchScreen(
          transport: DioSearchTransport(
            baseUrl: actions.baseUrl,
            accessToken: actions.accessTokenProvider,
          ),
        );
      },
    ),
    GoRoute(
      path: '/voice/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        final title = state.uri.queryParameters['title'] ?? 'Voice room';
        return VoiceRoomScreen(channelId: id, title: title);
      },
    ),
    GoRoute(
      path: '/call/video/:callId',
      builder: (context, state) {
        final callId = state.pathParameters['callId']!;
        final conversationId = state.uri.queryParameters['conversationId'];
        final title = state.uri.queryParameters['title'] ?? 'Video call';
        if (conversationId == null) {
          return const PlaceholderScreen(title: 'Call unavailable');
        }
        return VideoCallScreen(
          conversationId: conversationId,
          title: title,
          existingCallId: callId,
        );
      },
    ),
    GoRoute(
      path: '/call/voice/:callId',
      builder: (context, state) {
        final callId = state.pathParameters['callId']!;
        final conversationId = state.uri.queryParameters['conversationId'];
        final title = state.uri.queryParameters['title'] ?? 'Voice call';
        if (conversationId == null) {
          return const PlaceholderScreen(title: 'Call unavailable');
        }
        return VoiceRoomScreen(
          conversationId: conversationId,
          title: title,
          existingCallId: callId,
        );
      },
    ),
    GoRoute(
      path: '/room/:kind/:id',
      builder: (context, state) {
        final kind = state.pathParameters['kind'];
        final id = state.pathParameters['id']!;
        final roomKind = kind == 'channel'
            ? RoomKind.channel
            : RoomKind.conversation;
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
  const PulseMeshApp({this.callTransport, super.key});

  final CallTransport? callTransport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'PulseMesh',
      theme: buildPulseMeshTheme(),
      routerConfig: router,
      builder: (context, child) {
        return CallTransportScope(
          transport: callTransport,
          child: _IncomingCallHost(
            data: MobileDataScope.of(context),
            callTransport: callTransport,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

class _IncomingCallHost extends StatefulWidget {
  const _IncomingCallHost({
    required this.data,
    required this.child,
    this.callTransport,
  });

  final MobileDataController data;
  final CallTransport? callTransport;
  final Widget child;

  @override
  State<_IncomingCallHost> createState() => _IncomingCallHostState();
}

class _IncomingCallHostState extends State<_IncomingCallHost>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<CallNotificationAction>? _notificationActions;
  final Set<String> _seenCallIds = <String>{};
  _IncomingCallNotice? _incoming;
  _IncomingCallNotice? _pending;
  Timer? _ringTimer;
  AppLifecycleState _lifecycle =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    _notificationActions = MobilePushService.callActions.listen(
      (action) => unawaited(_handleNotificationAction(action)),
    );
  }

  @override
  void didUpdateWidget(covariant _IncomingCallHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _events?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _events = widget.data.realtimeEvents.listen(_handleRealtimeEvent);
  }

  void _dismissCall(String callId) {
    unawaited(MobilePushService.cancelCallNotification(callId));
    if (_incoming?.callId != callId && _pending?.callId != callId) return;
    _ringTimer?.cancel();
    _ringTimer = null;
    if (!mounted) return;
    setState(() {
      if (_incoming?.callId == callId) _incoming = null;
      if (_pending?.callId == callId) _pending = null;
    });
  }

  void _handleRealtimeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final payloadValue = event['payload'];
    if (payloadValue is! Map) return;
    final payload = Map<String, dynamic>.from(payloadValue);

    if (type == 'call.started') {
      final callId = payload['callId'] as String?;
      final conversationId = payload['conversationId'] as String?;
      final kind = payload['kind'] as String?;
      if (callId == null ||
          conversationId == null ||
          (kind != 'voice' && kind != 'video') ||
          _seenCallIds.contains(callId)) {
        return;
      }
      _seenCallIds.add(callId);
      unawaited(
        _resolveIncomingCall(
          callId: callId,
          conversationId: conversationId,
          kind: kind!,
        ),
      );
      return;
    }

    if (type == 'call.invite.updated') {
      final callId = payload['callId'] as String?;
      final userId = payload['userId'] as String?;
      final status = payload['status'] as String?;
      if (callId != null &&
          userId == widget.data.currentUserId &&
          status != null &&
          status != 'pending') {
        _dismissCall(callId);
      }
      return;
    }

    if (type == 'call.ended') {
      final callId = payload['callId'] as String?;
      if (callId != null) _dismissCall(callId);
    }
  }

  Future<void> _handleNotificationAction(CallNotificationAction action) async {
    await MobilePushService.cancelCallNotification(action.callId);
    if (!mounted) return;

    if (action.type == CallNotificationActionType.open) {
      _seenCallIds.remove(action.callId);
      await _resolveIncomingCall(
        callId: action.callId,
        conversationId: action.conversationId,
        kind: action.kind,
      );
      return;
    }

    final transport = widget.callTransport;
    if (transport == null) return;

    try {
      final call = await widget.data.refreshCall(action.callId);
      final invite = await transport.callInvite(action.callId);
      if (!mounted) return;
      if (call.status != 'active' || !invite.pending) {
        _dismissCall(action.callId);
        return;
      }

      if (action.type == CallNotificationActionType.decline) {
        await transport.respondToInvite(action.callId, status: 'declined');
        _dismissCall(action.callId);
        return;
      }

      _dismissCall(action.callId);
      final title = action.title?.trim().isNotEmpty == true
          ? action.title!.trim()
          : _incomingConversationTitle(
              widget.data,
              action.conversationId,
              call.createdBy,
            );
      _openCall(
        callId: action.callId,
        conversationId: action.conversationId,
        kind: action.kind,
        title: title,
      );
    } catch (_) {
      _dismissCall(action.callId);
    }
  }

  Future<void> _resolveIncomingCall({
    required String callId,
    required String conversationId,
    required String kind,
  }) async {
    try {
      final call = await widget.data.refreshCall(callId);
      if (!mounted ||
          call.status != 'active' ||
          call.createdBy == widget.data.currentUserId) {
        return;
      }

      final transport = widget.callTransport;
      final invite = transport == null
          ? null
          : await transport.callInvite(callId);
      if (invite != null && !invite.pending) return;

      final expiresAt =
          invite?.expiresAt ?? call.startedAt.add(const Duration(seconds: 45));
      if (!expiresAt.isAfter(DateTime.now().toUtc())) {
        if (transport != null) {
          unawaited(
            transport
                .respondToInvite(callId, status: 'missed')
                .catchError((_) => invite),
          );
        }
        return;
      }

      final notice = _IncomingCallNotice(
        callId: callId,
        conversationId: conversationId,
        kind: kind,
        title: _incomingConversationTitle(
          widget.data,
          conversationId,
          call.createdBy,
        ),
        expiresAt: expiresAt,
      );

      if (_lifecycle == AppLifecycleState.resumed) {
        setState(() => _incoming = notice);
        unawaited(HapticFeedback.mediumImpact());
      } else {
        setState(() => _pending = notice);
      }
      _scheduleExpiry(notice);
    } catch (_) {
      // A replayed call.started event may refer to a call that already ended.
    }
  }

  void _scheduleExpiry(_IncomingCallNotice notice) {
    _ringTimer?.cancel();
    final delay = notice.expiresAt.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) {
      unawaited(_markMissed(notice));
      return;
    }
    _ringTimer = Timer(delay, () => unawaited(_markMissed(notice)));
  }

  Future<void> _markMissed(_IncomingCallNotice notice) async {
    if (_incoming?.callId != notice.callId &&
        _pending?.callId != notice.callId) {
      return;
    }

    _dismissCall(notice.callId);
    final transport = widget.callTransport;
    if (transport == null) return;
    try {
      await transport.respondToInvite(notice.callId, status: 'missed');
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;

    if (state != AppLifecycleState.resumed) {
      final incoming = _incoming;
      if (incoming != null && mounted) {
        setState(() {
          _pending = incoming;
          _incoming = null;
        });
      }
      return;
    }

    final pending = _pending;
    if (pending != null) {
      unawaited(_restorePending(pending));
    }
  }

  Future<void> _restorePending(_IncomingCallNotice pending) async {
    try {
      final call = await widget.data.refreshCall(pending.callId);
      final transport = widget.callTransport;
      final invite = transport == null
          ? null
          : await transport.callInvite(pending.callId);
      if (!mounted) return;

      if (call.status != 'active' || (invite != null && !invite.pending)) {
        _dismissCall(pending.callId);
        return;
      }

      final restored = invite == null
          ? pending
          : _IncomingCallNotice(
              callId: pending.callId,
              conversationId: pending.conversationId,
              kind: pending.kind,
              title: pending.title,
              expiresAt: invite.expiresAt,
            );
      setState(() {
        _pending = null;
        _incoming = restored;
      });
      _scheduleExpiry(restored);
      unawaited(HapticFeedback.mediumImpact());
    } catch (_) {
      if (!mounted) return;
      _dismissCall(pending.callId);
    }
  }

  Future<void> _decline() async {
    final incoming = _incoming;
    if (incoming == null) return;

    _dismissCall(incoming.callId);
    final transport = widget.callTransport;
    if (transport == null) return;
    try {
      await transport.respondToInvite(incoming.callId, status: 'declined');
    } catch (_) {}
  }

  void _accept() {
    final incoming = _incoming;
    if (incoming == null) return;

    _dismissCall(incoming.callId);
    _openCall(
      callId: incoming.callId,
      conversationId: incoming.conversationId,
      kind: incoming.kind,
      title: incoming.title,
    );
  }

  void _openCall({
    required String callId,
    required String conversationId,
    required String kind,
    required String title,
  }) {
    final encodedConversation = Uri.encodeComponent(conversationId);
    final encodedTitle = Uri.encodeComponent(title);
    final path = kind == 'video'
        ? '/call/video/$callId'
        : '/call/voice/$callId';

    unawaited(
      router.push(
        '$path?conversationId=$encodedConversation&title=$encodedTitle',
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ringTimer?.cancel();
    _events?.cancel();
    _notificationActions?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _incoming;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (incoming != null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: SafeArea(
              bottom: false,
              child: _IncomingCallCard(
                notice: incoming,
                onAccept: _accept,
                onDecline: () => unawaited(_decline()),
              ),
            ),
          ),
      ],
    );
  }
}

class _IncomingCallNotice {
  const _IncomingCallNotice({
    required this.callId,
    required this.conversationId,
    required this.kind,
    required this.title,
    required this.expiresAt,
  });

  final String callId;
  final String conversationId;
  final String kind;
  final String title;
  final DateTime expiresAt;
}

class _IncomingCallCard extends StatelessWidget {
  const _IncomingCallCard({
    required this.notice,
    required this.onAccept,
    required this.onDecline,
  });

  final _IncomingCallNotice notice;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final video = notice.kind == 'video';

    return Material(
      elevation: 18,
      color: const Color(0xFF0C191F),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x5568E0CF)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFF173A3A),
              child: Icon(
                video ? Icons.videocam_rounded : Icons.call_rounded,
                color: const Color(0xFF68E0CF),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video ? 'Incoming video call' : 'Incoming voice call',
                    style: const TextStyle(
                      color: Color(0xFF9AF5E8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notice.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filled(
              tooltip: 'Decline',
              onPressed: onDecline,
              style: IconButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.call_end_rounded),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Accept',
              onPressed: onAccept,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF68E0CF),
                foregroundColor: Colors.black,
              ),
              icon: Icon(video ? Icons.videocam_rounded : Icons.call_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

String _incomingConversationTitle(
  MobileDataController data,
  String conversationId,
  String creatorId,
) {
  for (final conversation in data.inbox.conversations) {
    if (conversation.id != conversationId) continue;

    final name = conversation.name?.trim();
    if (name != null && name.isNotEmpty) return name;

    for (final member in conversation.members) {
      if (member.id != creatorId) continue;
      if (member.displayName.trim().isNotEmpty) {
        return member.displayName.trim();
      }
      if (member.username.trim().isNotEmpty) {
        return '@${member.username.trim()}';
      }
    }

    return conversation.kind == 'group'
        ? 'Group conversation'
        : 'Direct message';
  }

  return 'PulseMesh call';
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
          if (index == 2) {
            final transport = CallTransportScope.maybeOf(context);
            callActivityUnreadCount.value = 0;
            if (transport != null) {
              unawaited(transport.markHistoryRead());
            }
          }
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
            icon: CallActivityBadgeIcon(icon: Icons.notifications_none_rounded),
            selectedIcon: CallActivityBadgeIcon(
              icon: Icons.notifications_rounded,
            ),
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
  const _UnreadNavigationIcon({required this.count, required this.icon});

  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final base = Icon(icon);
    if (count <= 0) return base;

    return Badge(label: Text(count > 99 ? '99+' : '$count'), child: base);
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MobileDataScope.of(context);
    final workspace = data.selectedWorkspace;
    final textChannels = data.inbox.channels
        .where((channel) => !channel.isVoice)
        .toList();
    final voiceChannels = data.inbox.channels
        .where((channel) => channel.isVoice)
        .toList();

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
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
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
          if (data.offline || data.realtimeState != MobileRealtimeState.ready)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(child: _ConnectionBanner(data: data)),
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
              sliver: SliverToBoxAdapter(child: _NoWorkspaceState()),
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
              sliver: SliverToBoxAdapter(child: _SectionTitle(title: 'Voice')),
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
          SliverAppBar(
            floating: true,
            backgroundColor: const Color(0xFF071015),
            title: const Text(
              'Messages',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
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
              sliver: SliverToBoxAdapter(child: _ConnectionBanner(data: data)),
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
                  return _ConversationTile(conversation: conversations[index]);
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
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            copy,
            style: const TextStyle(color: Colors.white60, height: 1.4),
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
              style: const TextStyle(color: Colors.white70, fontSize: 13),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tileColor: channel.hasUnread
            ? const Color(0x1468E0CF)
            : Colors.transparent,
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
                  channel.unreadCount > 99 ? '99+' : '${channel.unreadCount}',
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: const Icon(Icons.graphic_eq_rounded, color: Color(0xFF68E0CF)),
        title: Text(channel.name),
        subtitle: Text(channel.visibility),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          context.push(
            '/voice/${channel.id}?title=${Uri.encodeComponent(channel.name)}',
          );
        },
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
  const _WorkspaceAvatar({required this.name, required this.size});

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
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.38),
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
  const _EmptySection({required this.icon, required this.message});

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
