import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/messages/room_message.dart';

void main() {
  test('parses cached sender metadata and delivery state', () {
    final message = RoomMessage.fromRow({
      'local_id': 'local-1',
      'server_id': 'message-1',
      'client_message_id': null,
      'body': 'API deployment finished',
      'sender_id': 'user-1',
      'sender_username': 'mohammed',
      'sender_display_name': 'Mohammed',
      'sender_avatar_url': null,
      'created_at': '2026-09-30T18:00:00.000Z',
      'edited_at': null,
      'status': 'sent',
      'encryption_version': null,
      'encrypted_payload': null,
    });

    expect(message.senderLabel, 'Mohammed');
    expect(message.body, 'API deployment finished');
    expect(message.failed, isFalse);
    expect(message.sending, isFalse);
  });


  test('parses reply references and reaction snapshots', () {
    final message = RoomMessage.fromRow({
      'local_id': 'message-2',
      'server_id': 'message-2',
      'client_message_id': null,
      'body': 'Looks good',
      'sender_id': 'user-2',
      'sender_username': 'lama',
      'sender_display_name': 'Lama',
      'sender_avatar_url': null,
      'reply_to_message_id': 'message-1',
      'reactions_json':
          '[{"emoji":"👍","count":4,"reactedByMe":true},{"emoji":"🔥","count":2,"reactedByMe":false}]',
      'created_at': '2026-09-30T18:01:00.000Z',
      'edited_at': null,
      'status': 'sent',
      'encryption_version': null,
      'encrypted_payload': null,
    });

    expect(message.replyToMessageId, 'message-1');
    expect(message.reactions, hasLength(2));
    expect(message.reactions.first.emoji, '👍');
    expect(message.reactions.first.count, 4);
    expect(message.reactions.first.reactedByMe, isTrue);
  });

  test('keeps optimistic messages identifiable as self', () {
    final message = RoomMessage.fromRow({
      'local_id': 'client-1',
      'server_id': null,
      'client_message_id': 'client-1',
      'body': 'Queued offline',
      'sender_id': null,
      'sender_username': null,
      'sender_display_name': null,
      'sender_avatar_url': null,
      'created_at': '2026-09-30T18:00:00.000Z',
      'edited_at': null,
      'status': 'sending',
      'encryption_version': null,
      'encrypted_payload': null,
    });

    expect(message.senderLabel, 'You');
    expect(message.sending, isTrue);
  });
}
