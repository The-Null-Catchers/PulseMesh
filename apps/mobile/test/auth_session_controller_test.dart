import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/auth/auth_models.dart';
import 'package:pulsemesh/auth/auth_session_controller.dart';
import 'package:pulsemesh/auth/auth_session_store.dart';
import 'package:pulsemesh/auth/auth_transport.dart';

class FakeAuthSessionStore implements AuthSessionStore {
  FakeAuthSessionStore({this.refreshToken});

  String? refreshToken;
  int writes = 0;
  int clears = 0;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    writes += 1;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearRefreshToken() async {
    clears += 1;
    refreshToken = null;
  }
}

class FakeAuthTransport implements AuthTransport {
  AuthTokens loginTokens = const AuthTokens(
    accessToken: 'access-login',
    refreshToken: 'refresh-login',
  );
  AuthTokens registerTokens = const AuthTokens(
    accessToken: 'access-register',
    refreshToken: 'refresh-register',
  );
  AuthTokens refreshTokens = const AuthTokens(
    accessToken: 'access-rotated',
    refreshToken: 'refresh-rotated',
  );

  Object? refreshError;
  Object? logoutError;
  String? lastRefreshToken;
  String? lastLogoutAccessToken;

  @override
  Future<AuthTokens> login(LoginCredentials credentials) async => loginTokens;

  @override
  Future<AuthTokens> register(RegisterCredentials credentials) async {
    return registerTokens;
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    lastRefreshToken = refreshToken;
    final error = refreshError;
    if (error != null) throw error;
    return refreshTokens;
  }

  @override
  Future<void> logout(String accessToken) async {
    lastLogoutAccessToken = accessToken;
    final error = logoutError;
    if (error != null) throw error;
  }
}

void main() {
  group('AuthSessionController', () {
    test('restore rotates and persists the replacement refresh token', () async {
      final store = FakeAuthSessionStore(refreshToken: 'refresh-old');
      final transport = FakeAuthTransport();
      final controller = AuthSessionController(
        transport: transport,
        store: store,
      );

      expect(await controller.restore(), isTrue);

      expect(transport.lastRefreshToken, 'refresh-old');
      expect(store.refreshToken, 'refresh-rotated');
      expect(store.writes, 1);
      expect(await controller.accessToken(), 'access-rotated');
      expect(controller.state, AuthSessionState.authenticated);
    });

    test('login persists refresh token and keeps access token in memory', () async {
      final store = FakeAuthSessionStore();
      final controller = AuthSessionController(
        transport: FakeAuthTransport(),
        store: store,
      );

      await controller.login(
        const LoginCredentials(
          email: 'user@example.com',
          password: 'password-password',
        ),
      );

      expect(store.refreshToken, 'refresh-login');
      expect(await controller.accessToken(), 'access-login');
      expect(controller.isAuthenticated, isTrue);
    });


    test('exposes the authenticated user id from access token claims', () async {
      final store = FakeAuthSessionStore();
      final transport = FakeAuthTransport();
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'sub': 'user-123'})))
          .replaceAll('=', '');
      transport.loginTokens = AuthTokens(
        accessToken: 'header.$payload.signature',
        refreshToken: 'refresh-login',
      );
      final controller = AuthSessionController(
        transport: transport,
        store: store,
      );

      await controller.login(
        const LoginCredentials(
          email: 'user@example.com',
          password: 'password-password',
        ),
      );

      expect(controller.currentUserId, 'user-123');
    });

    test('unauthorized restore clears an unusable refresh token', () async {
      final store = FakeAuthSessionStore(refreshToken: 'refresh-old');
      final transport = FakeAuthTransport()
        ..refreshError = const AuthTransportException(
          statusCode: 401,
          code: 'REFRESH_REUSE_DETECTED',
          message: 'Session family was revoked',
        );
      final controller = AuthSessionController(
        transport: transport,
        store: store,
      );

      await expectLater(controller.restore(), throwsA(isA<AuthTransportException>()));

      expect(store.refreshToken, isNull);
      expect(store.clears, 1);
      expect(await controller.accessToken(), isNull);
      expect(controller.state, AuthSessionState.signedOut);
    });

    test('transient restore failure keeps refresh token for retry', () async {
      final store = FakeAuthSessionStore(refreshToken: 'refresh-old');
      final transport = FakeAuthTransport()
        ..refreshError = const AuthTransportException(
          statusCode: 503,
          message: 'Service unavailable',
        );
      final controller = AuthSessionController(
        transport: transport,
        store: store,
      );

      await expectLater(controller.restore(), throwsA(isA<AuthTransportException>()));

      expect(store.refreshToken, 'refresh-old');
      expect(store.clears, 0);
      expect(await controller.accessToken(), isNull);
    });

    test('logout clears local session even when server logout fails', () async {
      final store = FakeAuthSessionStore();
      final transport = FakeAuthTransport();
      final controller = AuthSessionController(
        transport: transport,
        store: store,
      );

      await controller.login(
        const LoginCredentials(
          email: 'user@example.com',
          password: 'password-password',
        ),
      );
      transport.logoutError = const AuthTransportException(
        statusCode: 503,
        message: 'Network unavailable',
      );

      await expectLater(controller.logout(), throwsA(isA<AuthTransportException>()));

      expect(transport.lastLogoutAccessToken, 'access-login');
      expect(store.refreshToken, isNull);
      expect(await controller.accessToken(), isNull);
      expect(controller.state, AuthSessionState.signedOut);
    });
  });
}
