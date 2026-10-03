import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/notifications/call_notification_action.dart';

void main() {
  const action = CallNotificationAction(
    type: CallNotificationActionType.open,
    callId: 'call-1',
    conversationId: 'conversation-1',
    kind: 'video',
    title: 'Maya',
  );

  test('round trips call notification payload', () {
    final parsed = CallNotificationAction.tryParse(action.toPayload());

    expect(parsed, isNotNull);
    expect(parsed!.type, CallNotificationActionType.open);
    expect(parsed.callId, 'call-1');
    expect(parsed.conversationId, 'conversation-1');
    expect(parsed.kind, 'video');
    expect(parsed.title, 'Maya');
    expect(parsed.isVideo, isTrue);
  });

  test('maps native action ids', () {
    final accept = CallNotificationAction.tryParse(
      action.toPayload(),
      actionId: 'call.accept',
    );
    final decline = CallNotificationAction.tryParse(
      action.toPayload(),
      actionId: 'call.decline',
    );

    expect(accept?.type, CallNotificationActionType.accept);
    expect(decline?.type, CallNotificationActionType.decline);
  });

  test('rejects incomplete or unsupported call payloads', () {
    expect(CallNotificationAction.tryParse(null), isNull);
    expect(CallNotificationAction.tryParse('{}'), isNull);
    expect(
      CallNotificationAction.tryParse(
        '{"callId":"call-1","conversationId":"conversation-1","kind":"screen"}',
      ),
      isNull,
    );
  });
}
