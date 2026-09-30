import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../auth/auth_session_controller.dart';
import '../../config/app_config.dart';
import '../../offline/local_store.dart';
import '../../offline/models.dart';
import '../../offline/sync_engine.dart';
import '../../offline/sync_transport.dart';
import '../messages/message_actions_transport.dart';
import '../messages/room_message.dart';
import '../workspaces/workspace_models.dart';
import '../workspaces/workspace_transport.dart';
import 'inbox_models.dart';
import 'inbox_realtime.dart';
import 'inbox_transport.dart';

class MobileDataController extends ChangeNotifier {
  MobileDataController({
    required AuthSessionController authSession,
    required AppConfig config,
    required LocalMessageStore localStore,
    required WorkspaceTransport workspaceTransport,
    required InboxTransport inboxTransport,
    required MessageSyncTransport messageSyncTransport,
    required MessageActionsTransport messageActionsTransport,
  })  : _authSession = authSession,
        _config = config,
        _store = localStore,
        _workspaceTransport = workspaceTransport,
        _inboxTransport = inboxTransport,
        _messageActionsTransport = messageActionsTransport,
        _syncEngine = OfflineSyncEngine(
          store: localStore,
          transport: messageSyncTransport,
        );

  factory MobileDataController.live({
    required AuthSessionController authSession,
    required AppConfig config,
  }) {
    final localStore = LocalMessageStore();

    return MobileDataController(
      authSession: authSession,
      config: config,
      localStore: localStore,
      workspaceTransport: DioWorkspaceTransport(
        baseUrl: config.apiBaseUrl,
        accessToken: authSession.accessToken,
      ),
      inboxTransport: DioInboxTransport(
        baseUrl: config.apiBaseUrl,
        accessToken: authSession.accessToken,
      ),
      messageSyncTransport: DioMessageSyncTransport(
        baseUrl: config.apiBaseUrl,
        accessToken: authSession.accessToken,
      ),
      messageActionsTransport: DioMessageActionsTransport(
        baseUrl: config.apiBaseUrl,
        accessToken: authSession.accessToken,
      ),
    );
  }

  final AuthSessionController _authSession;
  final AppConfig _config;
  final LocalMessageStore _store;
  final WorkspaceTransport _workspaceTransport;
  final InboxTransport _inboxTransport;
  final MessageActionsTransport _messageActionsTransport;
  final OfflineSyncEngine _syncEngine;
  final Set<RoomRef> _openRooms = <RoomRef>{};
  final Map<RoomRef, Set<String>> _typingUsers = <RoomRef, Set<String>>{};

  List<WorkspaceSummary> _workspaces = const [];
  InboxSnapshot _inbox = const InboxSnapshot(
    channels: [],
    conversations: [],
  );
  String? _selectedWorkspaceId;
  bool _loading = true;
  bool _offline = false;
  Object? _error;
  MobileRealtimeState _realtimeState = MobileRealtimeState.disconnected;
  MobileInboxRealtimeBridge? _realtime;
  bool _disposed = false;

  List<WorkspaceSummary> get workspaces => _workspaces;
  InboxSnapshot get inbox => _inbox;
  String? get selectedWorkspaceId => _selectedWorkspaceId;
  bool get loading => _loading;
  bool get offline => _offline;
  Object? get error => _error;
  MobileRealtimeState get realtimeState => _realtimeState;
  int get totalUnread => _inbox.totalUnread;
  String? get currentUserId => _authSession.currentUserId;

  Set<String> typingUsersForRoom(RoomRef room) =>
      Set<String>.unmodifiable(_typingUsers[room] ?? const <String>{});

  WorkspaceSummary? get selectedWorkspace {
    final selectedId = _selectedWorkspaceId;
    if (selectedId == null) return null;

    for (final workspace in _workspaces) {
      if (workspace.id == selectedId) return workspace;
    }
    return null;
  }

  Future<void> initialize() async {
    await _syncEngine.start();
    await _loadCached();
    _notify();

    await refresh();
    await _startRealtime();
  }

  Future<void> refresh() async {
    if (_disposed) return;

    if (_workspaces.isEmpty && _inbox.conversations.isEmpty) {
      _loading = true;
      _notify();
    }

    try {
      final workspaces = await _workspaceTransport.listWorkspaces();
      _workspaces = workspaces;
      _normalizeSelectedWorkspace();

      await _store.cacheEntities(
        'workspaces',
        workspaces.map((workspace) => workspace.toJson()),
      );
      await _persistSelectedWorkspace();

      await refreshInbox();
      _offline = false;
      _error = null;
    } catch (error) {
      _offline = true;
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> refreshInbox() async {
    if (_disposed) return;

    final workspaceId = _selectedWorkspaceId;
    final conversationsFuture = _inboxTransport.conversations();
    final channels = workspaceId == null
        ? <ChannelSummary>[]
        : await _inboxTransport.channels(workspaceId);
    final conversations = await conversationsFuture;

    _inbox = InboxSnapshot(
      channels: channels,
      conversations: conversations,
    );

    if (workspaceId != null) {
      await _store.cacheEntities(
        'channels:$workspaceId',
        channels.map(_channelToJson),
      );
    }
    await _store.cacheEntities(
      'conversations',
      conversations.map(_conversationToJson),
    );

    _offline = false;
    _error = null;
    _notify();
  }

  Future<List<RoomMessage>> roomMessages(
    RoomRef room, {
    int limit = 100,
  }) async {
    final rows = await _store.messagesForRoom(room, limit: limit);
    return rows.map(RoomMessage.fromRow).toList(growable: false);
  }

  Future<void> openRoom(RoomRef room) async {
    if (_disposed) return;
    _openRooms.add(room);
    _syncEngine.watchRoom(room);
    _realtime?.watchRoom(room);
    await refreshRoom(room);
    await _markRoomReadBestEffort(room);
  }

  void closeRoom(RoomRef room) {
    _openRooms.remove(room);
    _typingUsers.remove(room);
    _syncEngine.unwatchRoom(room);
    _realtime?.unwatchRoom(room);
  }

  Future<void> refreshRoom(RoomRef room) async {
    if (_disposed) return;

    try {
      await _syncEngine.reconcileRoom(room);
      _offline = false;
      _error = null;
    } catch (error) {
      _offline = true;
      _error = error;
    } finally {
      _notify();
    }
  }

  Future<String> sendRoomMessage(
    RoomRef room,
    String body, {
    String? replyToMessageId,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(body, 'body', 'Message cannot be empty');
    }

    final clientMessageId = await _syncEngine.enqueueMessage(
      room: room,
      body: trimmed,
      replyToMessageId: replyToMessageId,
    );
    _notify();
    return clientMessageId;
  }

  Future<void> retryRoomMessage(String clientMessageId) async {
    await _syncEngine.retryFailed(clientMessageId);
    _notify();
  }

  Future<void> editRoomMessage({
    required RoomRef room,
    required String messageId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(body, 'body', 'Message cannot be empty');
    }

    await _messageActionsTransport.editMessage(
      messageId: messageId,
      body: trimmed,
    );
    await _syncEngine.reconcileRoom(room);
    _notify();
  }

  Future<void> deleteRoomMessage({
    required RoomRef room,
    required String messageId,
    String scope = 'everyone',
  }) async {
    await _messageActionsTransport.deleteMessage(
      messageId: messageId,
      scope: scope,
    );

    if (scope == 'self') {
      await _syncEngine.refreshRecentRoom(room);
    } else {
      await _syncEngine.reconcileRoom(room);
    }
    _notify();
  }

  Future<void> setRoomReaction({
    required RoomRef room,
    required String messageId,
    required String emoji,
    required bool active,
  }) async {
    await _messageActionsTransport.setReaction(
      messageId: messageId,
      emoji: emoji,
      active: active,
    );
    await _syncEngine.refreshRecentRoom(room);
    _notify();
  }

  void setTyping(RoomRef room, {required bool typing}) {
    _realtime?.sendTyping(room, typing: typing);
  }

  Future<void> selectWorkspace(String workspaceId) async {
    if (_disposed || workspaceId == _selectedWorkspaceId) return;
    if (!_workspaces.any((workspace) => workspace.id == workspaceId)) return;

    _selectedWorkspaceId = workspaceId;
    await _persistSelectedWorkspace();

    final cachedChannels = await _store.readEntities('channels:$workspaceId');
    _inbox = InboxSnapshot(
      channels: cachedChannels
          .map(ChannelSummary.fromJson)
          .toList(growable: false),
      conversations: _inbox.conversations,
    );
    _notify();

    try {
      await refreshInbox();
    } catch (error) {
      _offline = true;
      _error = error;
      _notify();
    }
  }

  Future<void> _loadCached() async {
    final cachedWorkspaces = await _store.readEntities('workspaces');
    _workspaces = cachedWorkspaces
        .map(WorkspaceSummary.fromJson)
        .toList(growable: false);

    final mobileState = await _store.readEntities('mobile_state');
    for (final state in mobileState) {
      if (state['id'] == 'selected_workspace') {
        _selectedWorkspaceId = state['workspaceId'] as String?;
        break;
      }
    }
    _normalizeSelectedWorkspace();

    final workspaceId = _selectedWorkspaceId;
    final cachedChannels = workspaceId == null
        ? const <Map<String, dynamic>>[]
        : await _store.readEntities('channels:$workspaceId');
    final cachedConversations = await _store.readEntities('conversations');

    _inbox = InboxSnapshot(
      channels: cachedChannels
          .map(ChannelSummary.fromJson)
          .toList(growable: false),
      conversations: cachedConversations
          .map(ConversationSummary.fromJson)
          .toList(growable: false),
    );
  }

  void _normalizeSelectedWorkspace() {
    final current = _selectedWorkspaceId;
    if (current != null &&
        _workspaces.any((workspace) => workspace.id == current)) {
      return;
    }

    _selectedWorkspaceId =
        _workspaces.isEmpty ? null : _workspaces.first.id;
  }

  Future<void> _persistSelectedWorkspace() {
    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) return Future<void>.value();

    return _store.cacheEntities(
      'mobile_state',
      [
        {
          'id': 'selected_workspace',
          'workspaceId': workspaceId,
        },
      ],
    );
  }

  Future<void> _startRealtime() async {
    if (_disposed || _realtime != null) return;

    final bridge = MobileInboxRealtimeBridge(
      webSocketUrl: _config.realtimeWebSocketUrl,
      ticketProvider: DioRealtimeTicketProvider(
        baseUrl: _config.apiBaseUrl,
        accessToken: _authSession.accessToken,
      ),
      localStore: _store,
      onInboxDirty: _refreshInboxBestEffort,
      onRoomDirty: _reconcileRoomBestEffort,
      onTypingChanged: (room, userIds) {
        if (_disposed) return;
        _typingUsers[room] = userIds;
        _notify();
      },
      onStateChanged: (state) {
        if (_disposed) return;
        _realtimeState = state;
        _notify();
      },
    );
    _realtime = bridge;
    for (final room in _openRooms) {
      bridge.watchRoom(room);
    }
    await bridge.start();
  }

  Future<void> _markRoomReadBestEffort(RoomRef room) async {
    try {
      final rows = await _store.messagesForRoom(room, limit: 1);
      if (rows.isEmpty) return;

      final lastReadMessageId = rows.first['server_id'] as String?;
      if (lastReadMessageId == null) return;

      if (room.kind == RoomKind.channel) {
        await _inboxTransport.markChannelRead(
          channelId: room.id,
          lastReadMessageId: lastReadMessageId,
        );
        _inbox = InboxSnapshot(
          channels: _inbox.channels
              .map(
                (channel) => channel.id == room.id
                    ? ChannelSummary(
                        id: channel.id,
                        name: channel.name,
                        unreadCount: 0,
                        kind: channel.kind,
                        visibility: channel.visibility,
                        position: channel.position,
                      )
                    : channel,
              )
              .toList(growable: false),
          conversations: _inbox.conversations,
        );
      } else {
        await _inboxTransport.markConversationRead(
          conversationId: room.id,
          lastReadMessageId: lastReadMessageId,
        );
        _inbox = InboxSnapshot(
          channels: _inbox.channels,
          conversations: _inbox.conversations
              .map(
                (conversation) => conversation.id == room.id
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
      }
      _notify();
    } catch (_) {
      // Read receipts are best-effort and must never block opening a room.
    }
  }

  Future<void> _reconcileRoomBestEffort(
    RoomRef room,
    String eventType,
  ) async {
    try {
      if (eventType == 'reaction.created' ||
          eventType == 'reaction.deleted') {
        await _syncEngine.refreshRecentRoom(room);
      } else {
        await _syncEngine.reconcileRoom(room);
      }
      _offline = false;
      _error = null;
      _notify();
    } catch (error) {
      if (_disposed) return;
      _offline = true;
      _error = error;
      _notify();
    }
  }

  Future<void> _refreshInboxBestEffort() async {
    try {
      await refreshInbox();
    } catch (error) {
      if (_disposed) return;
      _offline = true;
      _error = error;
      _notify();
    }
  }

  Map<String, dynamic> _channelToJson(ChannelSummary channel) => {
        'id': channel.id,
        'name': channel.name,
        'unread_count': channel.unreadCount,
        'kind': channel.kind,
        'visibility': channel.visibility,
        'position': channel.position,
      };

  Map<String, dynamic> _conversationToJson(
    ConversationSummary conversation,
  ) =>
      {
        'id': conversation.id,
        'kind': conversation.kind,
        'name': conversation.name,
        'avatar_url': conversation.avatarUrl,
        'encryption_mode': conversation.encryptionMode,
        'unread_count': conversation.unreadCount,
        'members': conversation.members
            .map(
              (member) => {
                'id': member.id,
                'username': member.username,
                'displayName': member.displayName,
                'avatarUrl': member.avatarUrl,
              },
            )
            .toList(growable: false),
      };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final realtime = _realtime;
    _realtime = null;
    if (realtime != null) {
      unawaited(realtime.stop());
    }
    unawaited(_syncEngine.dispose());
    unawaited(_store.close());
    super.dispose();
  }
}
