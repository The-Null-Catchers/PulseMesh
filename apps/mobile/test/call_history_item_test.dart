import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh_mobile/features/calls/call_transport.dart';

void main() {
  test('CallHistoryItem parses missed incoming calls', () {
    final item = CallHistoryItem.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'conversationId': '22222222-2222-4222-8222-222222222222',
      'createdBy': '33333333-3333-4333-8333-333333333333',
      'creatorUsername': 'caller',
      'creatorDisplayName': 'Caller',
      'kind': 'video',
      'status': 'ended',
      'startedAt': '2026-10-03T15:00:00.000Z',
      'endedAt': '2026-10-03T15:00:45.000Z',
      'inviteStatus': 'missed',
      'joined': false,
      'direction': 'incoming',
      'missed': true,
    });

    expect(item.kind, 'video');
    expect(item.missed, isTrue);
    expect(item.joined, isFalse);
    expect(item.direction, 'incoming');
    expect(item.inviteStatus, 'missed');
  });
}
