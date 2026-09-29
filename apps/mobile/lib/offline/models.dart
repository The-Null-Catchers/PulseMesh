enum RoomKind { channel, conversation }

extension RoomKindWire on RoomKind {
  String get wireName => switch (this) {
        RoomKind.channel => 'channel',
        RoomKind.conversation => 'conversation',
      };

  String get apiCollection => switch (this) {
        RoomKind.channel => 'channels',
        RoomKind.conversation => 'conversations',
      };

  static RoomKind parse(String value) => switch (value) {
        'channel' => RoomKind.channel,
        'conversation' => RoomKind.conversation,
        _ => throw ArgumentError.value(value, 'value', 'Unknown room kind'),
      };
}

class RoomRef {
  const RoomRef({required this.kind, required this.id});

  final RoomKind kind;
  final String id;

  String get cacheKey => '${kind.wireName}:$id';
  String get apiBase => '/${kind.apiCollection}/$id';

  @override
  bool operator ==(Object other) =>
      other is RoomRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

enum SyncChangeType { upsert, delete }

class SyncChange {
  const SyncChange({
    required this.cursor,
    required this.type,
    required this.messageId,
    required this.message,
  });

  final String cursor;
  final SyncChangeType type;
  final String messageId;
  final Map<String, dynamic>? message;

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    return SyncChange(
      cursor: json['cursor'] as String,
      type: json['type'] == 'delete'
          ? SyncChangeType.delete
          : SyncChangeType.upsert,
      messageId: json['messageId'] as String,
      message: json['message'] == null
          ? null
          : Map<String, dynamic>.from(json['message'] as Map),
    );
  }
}

class SyncPage {
  const SyncPage({
    required this.changes,
    required this.nextAfter,
    required this.hasMore,
  });

  final List<SyncChange> changes;
  final String nextAfter;
  final bool hasMore;

  factory SyncPage.fromJson(Map<String, dynamic> json) {
    final raw = json['changes'] as List<dynamic>? ?? const [];
    return SyncPage(
      changes: raw
          .map(
            (item) =>
                SyncChange.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      nextAfter: json['nextAfter'] as String? ?? '0',
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }
}

class SendAcknowledgement {
  const SendAcknowledgement({
    required this.id,
    required this.clientMessageId,
    required this.createdAt,
  });

  final String id;
  final String clientMessageId;
  final DateTime createdAt;
}

class PendingOutgoingMessage {
  const PendingOutgoingMessage({
    required this.clientMessageId,
    required this.room,
    required this.body,
    required this.replyToMessageId,
    required this.attachmentIds,
    required this.attempts,
  });

  final String clientMessageId;
  final RoomRef room;
  final String body;
  final String? replyToMessageId;
  final List<String> attachmentIds;
  final int attempts;
}
