import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'local_store.dart';
import 'models.dart';
import 'sync_policy.dart';
import 'sync_transport.dart';

class OfflineSyncEngine {
  OfflineSyncEngine({
    required LocalMessageStore store,
    required MessageSyncTransport transport,
    Connectivity? connectivity,
    Uuid? uuid,
  })  : _store = store,
        _transport = transport,
        _connectivity = connectivity ?? Connectivity(),
        _uuid = uuid ?? const Uuid();

  final LocalMessageStore _store;
  final MessageSyncTransport _transport;
  final Connectivity _connectivity;
  final Uuid _uuid;
  final Set<RoomRef> _watchedRooms = <RoomRef>{};

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _synchronizing = false;
  bool _disposed = false;

  void watchRoom(RoomRef room) {
    _watchedRooms.add(room);
  }

  void unwatchRoom(RoomRef room) {
    _watchedRooms.remove(room);
  }

  Future<void> start() async {
    if (_disposed || _connectivitySubscription != null) return;

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      if (_hasNetwork(results)) {
        unawaited(synchronize());
      }
    });

    final current = await _connectivity.checkConnectivity();
    if (_hasNetwork(current)) {
      await synchronize();
    }
  }

  Future<String> enqueueMessage({
    required RoomRef room,
    required String body,
    String? replyToMessageId,
    List<String> attachmentIds = const [],
    String? senderId,
  }) async {
    final clientMessageId = _uuid.v4();
    await _store.enqueueMessage(
      clientMessageId: clientMessageId,
      room: room,
      body: body,
      replyToMessageId: replyToMessageId,
      attachmentIds: attachmentIds,
      senderId: senderId,
    );

    unawaited(flushQueue());
    return clientMessageId;
  }

  Future<void> retryFailed(String clientMessageId) async {
    await _store.retryFailed(clientMessageId);
    await flushQueue();
  }

  Future<void> synchronize() async {
    if (_disposed || _synchronizing) return;
    _synchronizing = true;

    try {
      await flushQueue();
      for (final room in _watchedRooms.toList(growable: false)) {
        await reconcileRoom(room);
      }
    } finally {
      _synchronizing = false;
    }
  }

  Future<void> flushQueue() async {
    if (_disposed) return;

    final pending = await _store.pendingReady();
    for (final message in pending) {
      await _store.markAttempt(message.clientMessageId);

      try {
        final acknowledgement = await _transport.send(message);
        await _store.markSent(acknowledgement);
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        final description =
            'HTTP ${status ?? 'network'}: ${error.message ?? 'send failed'}';

        if (isPermanentHttpStatus(status)) {
          await _store.markFailed(
            message.clientMessageId,
            error: description,
          );
        } else {
          await _store.scheduleRetry(
            message.clientMessageId,
            nextAttemptAt: DateTime.now().toUtc().add(
                  retryDelay(message.attempts + 1),
                ),
            error: description,
          );
        }
      } catch (error) {
        await _store.scheduleRetry(
          message.clientMessageId,
          nextAttemptAt: DateTime.now().toUtc().add(
                retryDelay(message.attempts + 1),
              ),
          error: error.toString(),
        );
      }
    }
  }

  Future<void> reconcileRoom(RoomRef room) async {
    if (_disposed) return;

    var state = await _store.syncState(room);

    if (!state.bootstrapped) {
      // Capture the high-water mark before reading recent history. Messages
      // created during the history request are either already present there
      // or replayed by the incremental sync below, and local upserts dedupe.
      final cursor = await _transport.currentCursor(room);
      final recent = await _transport.recentMessages(room);
      await _store.bootstrapRoom(
        room,
        cursor: cursor,
        recentMessages: recent,
      );
      state = RoomSyncState(cursor: cursor, bootstrapped: true);
    }

    var cursor = state.cursor;
    for (var pageCount = 0; pageCount < 50; pageCount++) {
      final page = await _transport.sync(room, after: cursor);
      await _store.applySyncPage(room, page);
      cursor = page.nextAfter;

      if (!page.hasMore) return;
    }

    throw StateError(
      'Sync page safety limit reached for ${room.cacheKey}',
    );
  }

  bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  Future<void> dispose() async {
    _disposed = true;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }
}
