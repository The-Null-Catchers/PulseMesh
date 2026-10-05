import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/auth/auth_models.dart';
import 'package:pulsemesh/auth/auth_session_controller.dart';
import 'package:pulsemesh/auth/auth_session_store.dart';
import 'package:pulsemesh/auth/auth_transport.dart';
import 'package:pulsemesh/config/app_config.dart';
import 'package:pulsemesh/features/inbox/inbox_models.dart';
import 'package:pulsemesh/features/inbox/inbox_transport.dart';
import 'package:pulsemesh/features/inbox/mobile_data_controller.dart';
import 'package:pulsemesh/features/inbox/mobile_data_scope.dart';
import 'package:pulsemesh/features/messages/message_actions_transport.dart';
import 'package:pulsemesh/features/messages/saved_message.dart';
import 'package:pulsemesh/features/workspaces/workspace_models.dart';
import 'package:pulsemesh/features/workspaces/workspace_transport.dart';
import 'package:pulsemesh/main.dart';
import 'package:pulsemesh/offline/local_store.dart';
import 'package:pulsemesh/offline/models.dart';
import 'package:pulsemesh/offline/sync_transport.dart';

class EmptyWorkspaceTransport implements WorkspaceTransport {
  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => const [];
}

class EmptyInboxTransport implements InboxTransport {
  @override
  Future<List<ChannelSummary>> channels(String workspaceId) async => const [];

  @override
  Future<List<ConversationSummary>> conversations() async => const [];

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

class EmptyMessageSyncTransport implements MessageSyncTransport {
  @override
  Future<String> currentCursor(RoomRef room) async => '0';

  @override
  Future<List<Map<String, dynamic>>> recentMessages(
    RoomRef room, {
    int limit = 50,
  }) async =>
      const [];

  @override
  Future<SendAcknowledgement> send(PendingOutgoingMessage message) {
    throw UnimplementedError();
  }

  @override
  Future<SyncPage> sync(
    RoomRef room, {
    required String after,
    int limit = 100,
  }) async =>
      const SyncPage(changes: [], nextAfter: '0', hasMore: false);
}

class EmptyMessageActionsTransport implements MessageActionsTransport {
  @override
  Future<void> deleteMessage({
    required String messageId,
    required String scope,
  }) async {}

  @override
  Future<void> editMessage({
    required String messageId,
    required String body,
  }) async {}

  @override
  Future<void> setReaction({
    required String messageId,
    required String emoji,
    required bool active,
  }) async {}

  @override
  Future<void> bookmarkMessage({
    required String messageId,
    String? note,
  }) async {}

  @override
  Future<List<SavedMessage>> savedMessages({int limit = 100}) async => const [];

  @override
  Future<void> removeBookmark({required String messageId}) async {}

  @override
  Future<void> pinMessage({
    required String messageId,
    required bool active,
  }) async {}

  @override
  Future<void> forwardMessage({
    required String messageId,
    required String destinationKind,
    required String destinationId,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> thread(String messageId) async => const [];

  @override
  Future<void> sendThreadReply({
    required String messageId,
    required String body,
  }) async {}
}

class EmptyAuthStore implements AuthSessionStore {
  @override
  Future<void> clearRefreshToken() async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {}
}

class EmptyAuthTransport implements AuthTransport {
  @override
  Future<AuthTokens> login(LoginCredentials credentials) {
    throw UnimplementedError();
  }

  @override
  Future<void> logout(String accessToken) async {}

  @override
  Future<AuthTokens> refresh(String refreshToken) {
    throw UnimplementedError();
  }

  @override
  Future<AuthTokens> register(RegisterCredentials credentials) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('PulseMesh renders the authenticated mobile shell', (tester) async {
    final authSession = AuthSessionController(
      transport: EmptyAuthTransport(),
      store: EmptyAuthStore(),
    );
    final data = MobileDataController(
      authSession: authSession,
      config: const AppConfig(
        apiBaseUrl: 'http://localhost:4000',
        realtimeWebSocketUrl: 'ws://localhost:4000/realtime',
      ),
      localStore: LocalMessageStore(databaseName: 'pulsemesh_smoke_test'),
      workspaceTransport: EmptyWorkspaceTransport(),
      inboxTransport: EmptyInboxTransport(),
      messageSyncTransport: EmptyMessageSyncTransport(),
      messageActionsTransport: EmptyMessageActionsTransport(),
    );
    addTearDown(data.dispose);

    await tester.pumpWidget(
      MobileDataScope(
        controller: data,
        child: const PulseMeshApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
