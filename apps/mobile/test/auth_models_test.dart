import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/auth/auth_models.dart';

void main() {
  test('AuthTokens requires both access and refresh tokens', () {
    final tokens = AuthTokens.fromJson({
      'accessToken': 'access-token',
      'refreshToken': 'refresh-token',
    });

    expect(tokens.accessToken, 'access-token');
    expect(tokens.refreshToken, 'refresh-token');

    expect(
      () => AuthTokens.fromJson({'accessToken': 'access-token'}),
      throwsFormatException,
    );
  });

  test('credential payload includes optional device metadata when present', () {
    const credentials = LoginCredentials(
      email: 'user@example.com',
      password: 'password-password',
      device: 'PulseMesh Mobile',
      os: 'android',
    );

    expect(credentials.toJson(), {
      'email': 'user@example.com',
      'password': 'password-password',
      'device': 'PulseMesh Mobile',
      'os': 'android',
    });
  });
}
