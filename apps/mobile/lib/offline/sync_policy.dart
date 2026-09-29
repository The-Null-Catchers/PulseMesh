Duration retryDelay(int attempts) {
  var exponent = attempts - 1;
  if (exponent < 0) exponent = 0;
  if (exponent > 6) exponent = 6;

  var seconds = 1 << exponent;
  if (seconds > 60) seconds = 60;
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
