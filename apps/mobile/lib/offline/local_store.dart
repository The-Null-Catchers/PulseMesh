import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

class RoomSyncState {
  const RoomSyncState({
    required this.cursor,
    required this.bootstrapped,
  });

  final String cursor;
  final bool bootstrapped;
}

class LocalMessageStore {
  LocalMessageStore({this.databaseName = 'pulsemesh_cache'});

  final String databaseName;
  Future<Database>? _databaseFuture;

  Future<Database> get _database =>
      _databaseFuture ??= _openDatabase();

  Future<Database> _openDatabase() async {
    final root = await getDatabasesPath();
    return openDatabase(
      '$root/$databaseName.sqlite',
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE cached_messages ADD COLUMN encryption_version TEXT',
          );
          await db.execute(
            'ALTER TABLE cached_messages ADD COLUMN encrypted_payload TEXT',
          );
          await db.execute(
            'ALTER TABLE outgoing_queue ADD COLUMN encryption_version TEXT',
          );
          await db.execute(
            'ALTER TABLE outgoing_queue ADD COLUMN encrypted_payload TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE cached_messages ADD COLUMN sender_username TEXT',
          );
          await db.execute(
            'ALTER TABLE cached_messages ADD COLUMN sender_display_name TEXT',
          );
          await db.execute(
            'ALTER TABLE cached_messages ADD COLUMN sender_avatar_url TEXT',
          );
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_messages (
            local_id TEXT PRIMARY KEY,
            server_id TEXT UNIQUE,
            client_message_id TEXT UNIQUE,
            room_kind TEXT NOT NULL,
            room_id TEXT NOT NULL,
            body TEXT NOT NULL,
            encryption_version TEXT,
            encrypted_payload TEXT,
            sender_id TEXT,
            sender_username TEXT,
            sender_display_name TEXT,
            sender_avatar_url TEXT,
            created_at TEXT NOT NULL,
            edited_at TEXT,
            status TEXT NOT NULL,
            attachments_json TEXT NOT NULL DEFAULT '[]',
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE INDEX cached_messages_room_order_idx
          ON cached_messages(room_kind,room_id,created_at DESC,server_id DESC)
        ''');
        await db.execute('''
          CREATE TABLE outgoing_queue (
            client_message_id TEXT PRIMARY KEY,
            local_id TEXT NOT NULL,
            room_kind TEXT NOT NULL,
            room_id TEXT NOT NULL,
            body TEXT NOT NULL,
            encryption_version TEXT,
            encrypted_payload TEXT,
            reply_to_message_id TEXT,
            attachment_ids_json TEXT NOT NULL DEFAULT '[]',
            attempts INTEGER NOT NULL DEFAULT 0,
            queue_state TEXT NOT NULL DEFAULT 'pending',
            next_attempt_at TEXT NOT NULL,
            last_error TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY(local_id) REFERENCES cached_messages(local_id)
              ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE INDEX outgoing_queue_ready_idx
          ON outgoing_queue(queue_state,next_attempt_at,created_at)
        ''');
        await db.execute('''
          CREATE TABLE sync_state (
            room_kind TEXT NOT NULL,
            room_id TEXT NOT NULL,
            cursor TEXT NOT NULL DEFAULT '0',
            bootstrapped INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(room_kind,room_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_entities (
            kind TEXT NOT NULL,
            id TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(kind,id)
          )
        ''');
      },
    );
  }

  Future<void> cacheEntities(
    String kind,
    Iterable<Map<String, dynamic>> entities,
  ) async {
    final db = await _database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();

    for (final entity in entities) {
      final id = entity['id'];
      if (id is! String || id.isEmpty) continue;
      batch.insert(
        'cached_entities',
        {
          'kind': kind,
          'id': id,
          'payload_json': jsonEncode(entity),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> readEntities(
    String kind,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'cached_entities',
      where: 'kind=?',
      whereArgs: [kind],
      orderBy: 'updated_at DESC',
    );

    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['payload_json']! as String) as Map,
          ),
        )
        .toList(growable: false);
  }

  Future<int> realtimeSequence() async {
    final entities = await readEntities('realtime_state');
    for (final entity in entities) {
      if (entity['id'] != 'sequence') continue;
      final value = entity['value'];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Future<void> writeRealtimeSequence(int sequence) {
    return cacheEntities(
      'realtime_state',
      [
        {
          'id': 'sequence',
          'value': sequence,
        },
      ],
    );
  }

  Future<void> enqueueMessage({
    required String clientMessageId,
    required RoomRef room,
    required String body,
    String? encryptionVersion,
    String? encryptedPayload,
    String? replyToMessageId,
    List<String> attachmentIds = const [],
    String? senderId,
    DateTime? localCreatedAt,
  }) async {
    final db = await _database;
    final now = (localCreatedAt ?? DateTime.now()).toUtc();
    final timestamp = now.toIso8601String();

    await db.transaction((txn) async {
      await txn.insert(
        'cached_messages',
        {
          'local_id': clientMessageId,
          'server_id': null,
          'client_message_id': clientMessageId,
          'room_kind': room.kind.wireName,
          'room_id': room.id,
          'body': body,
          'encryption_version': encryptionVersion,
          'encrypted_payload': encryptedPayload,
          'sender_id': senderId,
          'sender_username': null,
          'sender_display_name': null,
          'sender_avatar_url': null,
          'created_at': timestamp,
          'edited_at': null,
          'status': 'sending',
          'attachments_json': '[]',
          'updated_at': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      await txn.insert(
        'outgoing_queue',
        {
          'client_message_id': clientMessageId,
          'local_id': clientMessageId,
          'room_kind': room.kind.wireName,
          'room_id': room.id,
          'body': body,
          'encryption_version': encryptionVersion,
          'encrypted_payload': encryptedPayload,
          'reply_to_message_id': replyToMessageId,
          'attachment_ids_json': jsonEncode(attachmentIds),
          'attempts': 0,
          'queue_state': 'pending',
          'next_attempt_at': timestamp,
          'last_error': null,
          'created_at': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  Future<List<Map<String, Object?>>> messagesForRoom(
    RoomRef room, {
    int limit = 100,
  }) async {
    final db = await _database;
    return db.query(
      'cached_messages',
      where: 'room_kind=? AND room_id=?',
      whereArgs: [room.kind.wireName, room.id],
      orderBy: 'created_at DESC,server_id DESC',
      limit: limit,
    );
  }

  Future<List<PendingOutgoingMessage>> pendingReady({
    int limit = 25,
    DateTime? now,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'outgoing_queue',
      where: "queue_state='pending' AND next_attempt_at<=?",
      whereArgs: [(now ?? DateTime.now()).toUtc().toIso8601String()],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return rows.map((row) {
      final attachmentIds =
          (jsonDecode(row['attachment_ids_json']! as String) as List<dynamic>)
              .cast<String>();
      return PendingOutgoingMessage(
        clientMessageId: row['client_message_id']! as String,
        room: RoomRef(
          kind: parseRoomKind(row['room_kind']! as String),
          id: row['room_id']! as String,
        ),
        body: row['body']! as String,
        encryptionVersion: row['encryption_version'] as String?,
        encryptedPayload: row['encrypted_payload'] as String?,
        replyToMessageId: row['reply_to_message_id'] as String?,
        attachmentIds: attachmentIds,
        attempts: row['attempts']! as int,
      );
    }).toList(growable: false);
  }

  Future<void> markAttempt(String clientMessageId) async {
    final db = await _database;
    await db.rawUpdate(
      '''
      UPDATE outgoing_queue
      SET attempts=attempts+1
      WHERE client_message_id=?
      ''',
      [clientMessageId],
    );
  }

  Future<void> scheduleRetry(
    String clientMessageId, {
    required DateTime nextAttemptAt,
    required String error,
  }) async {
    final db = await _database;
    await db.update(
      'outgoing_queue',
      {
        'queue_state': 'pending',
        'next_attempt_at': nextAttemptAt.toUtc().toIso8601String(),
        'last_error': error,
      },
      where: 'client_message_id=?',
      whereArgs: [clientMessageId],
    );
  }

  Future<void> markFailed(
    String clientMessageId, {
    required String error,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.update(
        'outgoing_queue',
        {'queue_state': 'failed', 'last_error': error},
        where: 'client_message_id=?',
        whereArgs: [clientMessageId],
      );
      await txn.update(
        'cached_messages',
        {
          'status': 'failed',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'client_message_id=?',
        whereArgs: [clientMessageId],
      );
    });
  }

  Future<void> retryFailed(String clientMessageId) async {
    final db = await _database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'outgoing_queue',
        {
          'queue_state': 'pending',
          'next_attempt_at': now,
          'last_error': null,
        },
        where: 'client_message_id=?',
        whereArgs: [clientMessageId],
      );
      await txn.update(
        'cached_messages',
        {'status': 'sending', 'updated_at': now},
        where: 'client_message_id=?',
        whereArgs: [clientMessageId],
      );
    });
  }

  Future<void> markSent(
    SendAcknowledgement acknowledgement,
  ) async {
    final db = await _database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.update(
        'cached_messages',
        {
          'server_id': acknowledgement.id,
          'status': 'sent',
          'created_at': acknowledgement.createdAt.toIso8601String(),
          'updated_at': now,
        },
        where: 'client_message_id=?',
        whereArgs: [acknowledgement.clientMessageId],
      );
      await txn.delete(
        'outgoing_queue',
        where: 'client_message_id=?',
        whereArgs: [acknowledgement.clientMessageId],
      );
    });
  }

  Future<RoomSyncState> syncState(RoomRef room) async {
    final db = await _database;
    final rows = await db.query(
      'sync_state',
      where: 'room_kind=? AND room_id=?',
      whereArgs: [room.kind.wireName, room.id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const RoomSyncState(cursor: '0', bootstrapped: false);
    }

    final row = rows.first;
    return RoomSyncState(
      cursor: row['cursor']! as String,
      bootstrapped: (row['bootstrapped']! as int) == 1,
    );
  }

  Future<void> bootstrapRoom(
    RoomRef room, {
    required String cursor,
    required List<Map<String, dynamic>> recentMessages,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      for (final message in recentMessages) {
        await _upsertServerMessage(txn, room, message);
      }
      await _writeSyncState(txn, room, cursor, bootstrapped: true);
      await _pruneRoom(txn, room);
    });
  }

  Future<void> applySyncPage(
    RoomRef room,
    SyncPage page,
  ) async {
    final db = await _database;
    await db.transaction((txn) async {
      for (final change in page.changes) {
        if (change.type == SyncChangeType.delete) {
          await txn.delete(
            'cached_messages',
            where: 'server_id=?',
            whereArgs: [change.messageId],
          );
          continue;
        }

        final message = change.message;
        if (message != null) {
          await _upsertServerMessage(txn, room, message);
        }
      }

      await _writeSyncState(
        txn,
        room,
        page.nextAfter,
        bootstrapped: true,
      );
      await _pruneRoom(txn, room);
    });
  }

  Future<void> _pruneRoom(
    DatabaseExecutor db,
    RoomRef room, {
    int keep = 500,
  }) async {
    await db.rawDelete(
      '''
      DELETE FROM cached_messages
      WHERE room_kind=?
        AND room_id=?
        AND status='sent'
        AND local_id NOT IN (
          SELECT local_id
          FROM cached_messages
          WHERE room_kind=? AND room_id=?
          ORDER BY created_at DESC,server_id DESC
          LIMIT ?
        )
      ''',
      [
        room.kind.wireName,
        room.id,
        room.kind.wireName,
        room.id,
        keep,
      ],
    );
  }

  Future<void> _upsertServerMessage(
    DatabaseExecutor db,
    RoomRef room,
    Map<String, dynamic> message,
  ) async {
    final serverId = message['id'] as String?;
    if (serverId == null || serverId.isEmpty) return;

    final clientMessageId = message['clientMessageId'] as String?;
    List<Map<String, Object?>> existing = const [];

    if (clientMessageId != null) {
      existing = await db.query(
        'cached_messages',
        columns: ['local_id'],
        where: 'client_message_id=?',
        whereArgs: [clientMessageId],
        limit: 1,
      );
    }
    if (existing.isEmpty) {
      existing = await db.query(
        'cached_messages',
        columns: ['local_id'],
        where: 'server_id=?',
        whereArgs: [serverId],
        limit: 1,
      );
    }

    final localId = existing.isEmpty
        ? serverId
        : existing.first['local_id']! as String;
    final sender = message['sender'] == null
        ? null
        : Map<String, dynamic>.from(message['sender'] as Map);
    final createdAt = message['createdAt'] as String? ??
        DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'cached_messages',
      {
        'local_id': localId,
        'server_id': serverId,
        'client_message_id': clientMessageId,
        'room_kind': room.kind.wireName,
        'room_id': room.id,
        'body': message['body'] as String? ?? '',
        'encryption_version': message['encryptionVersion'] as String?,
        'encrypted_payload': message['encryptedPayload'] as String?,
        'sender_id': sender?['id'] as String?,
        'sender_username': sender?['username'] as String?,
        'sender_display_name': sender?['displayName'] as String?,
        'sender_avatar_url': sender?['avatarUrl'] as String?,
        'created_at': createdAt,
        'edited_at': message['editedAt'] as String?,
        'status': 'sent',
        'attachments_json': jsonEncode(
          message['attachments'] as List<dynamic>? ?? const [],
        ),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (clientMessageId != null) {
      await db.delete(
        'outgoing_queue',
        where: 'client_message_id=?',
        whereArgs: [clientMessageId],
      );
    }
  }

  Future<void> _writeSyncState(
    DatabaseExecutor db,
    RoomRef room,
    String cursor, {
    required bool bootstrapped,
  }) async {
    await db.insert(
      'sync_state',
      {
        'room_kind': room.kind.wireName,
        'room_id': room.id,
        'cursor': cursor,
        'bootstrapped': bootstrapped ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    final future = _databaseFuture;
    _databaseFuture = null;
    if (future != null) {
      await (await future).close();
    }
  }
}
