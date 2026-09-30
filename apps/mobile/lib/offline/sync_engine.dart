import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'local_store.dart';
import 'models.dart';
import 'sync_policy.dart';
import 'sync_transport.dart';

typedef BackgroundSyncErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

class OfflineSyncEngine {
  OfflineSyncEngine({
    required LocalMessageStore store,
    required MessageSyncTransport transport,
    Connectivity? connectivity,
    Uuid? uuid,
    BackgroundSyncErrorHandler? onBackgroundError,
  })  : _store = store,
        _transport = transport,
        _connectivity = connectivity ?? Connectivity(),
        _uuid = uuid ?? const Uuid(),
        _onBackgroundError = onBackgroundError;

  final LocalMessageStore _store;
  final MessageSyncTransport _transport;
  final Connectivity _connectivity;
  final Uuid _uuid;
  final BackgroundSyncErrorHandler? _onBackgroundError;
  final Set<RoomRef> _watchedRooms = <RoomRef>{};

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Future<void>? _synchronizeFuture;
  Future<void>? _flushFuture;
  final Map<RoomRef, Future<void>> _roomReconcileFutures =
      <RoomRef, Future<void>>{};
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
        _triggerBackgroundSync();
      }
    });

    try {
      final current = await _connectivity.checkConnectivity();
      if (_hasNetwork(current)) {
        _triggerBackgroundSync();
      }
    } catch (error, stackTrace) {
      _onBackgroundError?.call(error, stackTrace);
    }
  }

  Future<String> enqueueMessage({
    required RoomRef room,
    required String body,
    String? encryptionVersion,
    String? encryptedPayload,
    String? replyToMessageId,
    List<String> attachmentIds = const [],
    String? senderId,
  }) async {
    final clientMessageId = _uuid.v4();
    await _store.enqueueMessage(
      clientMessageId: clientMessageId,
      room: room,
      body: body,
      encryptionVersion: encryptionVersion,
      encryptedPayload: encryptedPayload,
      replyToMessageId: replyToMessageId,
      attachmentIds: attachmentIds,
      senderId: senderId,
    );

    unawaited(_bestEffortFlush());
    return clientMessageId;
  }

  Future<void> retryFailed(String clientMessageId) async {
    await _store.retryFailed(clientMessageId);
    await flushQueue();
  }

  Future<void> synchronize() {
    if (_disposed) return Future<void>.value();

    final existing = _synchronizeFuture;
    if (existing != null) return existing;

    late final Future<void> future;
    future = _runSynchronize().whenComplete(() {
      if (identical(_synchronizeFuture, future)) {
        _synchronizeFuture = null;
      }
    });
    _synchronizeFuture = future;
    return future;
  }

  Future<void> _runSynchronize() async {
    await flushQueue();
    for (final room in _watchedRooms.toList(growable: false)) {
      await reconcileRoom(room);
    }
  }

  Future<void> flushQueue() {
    if (_disposed) return Future<void>.value();

    final existing = _flushFuture;
    if (existing != null) return existing;

    late final Future<void> future;
    future = _runFlushQueue().whenComplete(() {
      if (identical(_flushFuture, future)) {
        _flushFuture = null;
      }
    });
    _flushFuture = future;
    return future;
  }

  Future<void> _runFlushQueue() async {
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

  Future<void> reconcileRoom(RoomRef room) {
    if (_disposed) return Future<void>.value();

    final existing = _roomReconcileFutures[room];
    if (existing != null) return existing;

    late final Future<void> future;
    future = _runReconcileRoom(room).whenComplete(() {
      if (identical(_roomReconcileFutures[room], future)) {
        _roomReconcileFutures.remove(room);
      }
    });
    _roomReconcileFutures[room] = future;
    return future;
  }

  Future<void> _runReconcileRoom(RoomRef room) async {
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

  void _triggerBackgroundSync() {
    unawaited(_bestEffortSynchronize());
  }

  Future<void> _bestEffortSynchronize() async {
    try {
      await synchronize();
    } catch (error, stackTrace) {
      _onBackgroundError?.call(error, stackTrace);
    }
  }

  Future<void> _bestEffortFlush() async {
    try {
      await flushQueue();
    } catch (error, stackTrace) {
      _onBackgroundError?.call(error, stackTrace);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }
}
