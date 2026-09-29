import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/offline/sync_policy.dart';

void main() {
  group('retryDelay', () {
    test('uses capped exponential backoff', () {
      expect(retryDelay(1), const Duration(seconds: 1));
      expect(retryDelay(2), const Duration(seconds: 2));
      expect(retryDelay(4), const Duration(seconds: 8));
      expect(retryDelay(20), const Duration(seconds: 60));
    });
  });

  group('isPermanentHttpStatus', () {
    test('keeps transient and authentication failures retryable', () {
      expect(isPermanentHttpStatus(null), isFalse);
      expect(isPermanentHttpStatus(401), isFalse);
      expect(isPermanentHttpStatus(408), isFalse);
      expect(isPermanentHttpStatus(429), isFalse);
      expect(isPermanentHttpStatus(503), isFalse);
    });

    test('marks deterministic client failures as permanent', () {
      expect(isPermanentHttpStatus(400), isTrue);
      expect(isPermanentHttpStatus(403), isTrue);
      expect(isPermanentHttpStatus(404), isTrue);
      expect(isPermanentHttpStatus(422), isTrue);
    });
  });
}
