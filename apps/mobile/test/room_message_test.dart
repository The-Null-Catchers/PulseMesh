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
