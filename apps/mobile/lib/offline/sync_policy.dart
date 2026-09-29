import 'dart:math' as math;

Duration retryDelay(int attempts) {
  final exponent = math.max(0, math.min(attempts - 1, 6));
  final seconds = math.min(60, 1 << exponent);
  return Duration(seconds: seconds);
}

bool isPermanentHttpStatus(int? statusCode) {
  if (statusCode == null) return false;
  if (statusCode < 400 || statusCode >= 500) return false;

  return switch (statusCode) {
    401 || 408 || 409 || 425 || 429 => false,
    _ => true,
  };
}
