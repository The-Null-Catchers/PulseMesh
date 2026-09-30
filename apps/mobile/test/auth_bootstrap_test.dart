import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/auth/auth_bootstrap.dart';
import 'package:pulsemesh/auth/auth_models.dart';
import 'package:pulsemesh/auth/auth_session_controller.dart';
import 'package:pulsemesh/auth/auth_session_store.dart';
import 'package:pulsemesh/auth/auth_transport.dart';

class MemorySessionStore implements AuthSessionStore {
  String? refreshToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearRefreshToken() async {
    refreshToken = null;
  }
}

class WidgetAuthTransport implements AuthTransport {
  @override
  Future<AuthTokens> login(LoginCredentials credentials) async {
    return const AuthTokens(
      accessToken: 'access-login',
      refreshToken: 'refresh-login',
    );
  }

  @override
  Future<AuthTokens> register(RegisterCredentials credentials) async {
    return const AuthTokens(
      accessToken: 'access-register',
      refreshToken: 'refresh-register',
    );
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    return const AuthTokens(
      accessToken: 'access-restored',
      refreshToken: 'refresh-restored',
    );
  }

  @override
  Future<void> logout(String accessToken) async {}
}

void main() {
  testWidgets('signs in and opens the authenticated app', (tester) async {
    final controller = AuthSessionController(
      transport: WidgetAuthTransport(),
      store: MemorySessionStore(),
    );

    await tester.pumpWidget(
      MobileAuthBootstrap(
        controller: controller,
        authenticatedAppBuilder: (_) => const MaterialApp(
          home: Scaffold(body: Text('Authenticated workspace')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'password-password',
    );
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Authenticated workspace'), findsOneWidget);
    expect(await controller.accessToken(), 'access-login');
  });

  testWidgets('can switch to account creation mode', (tester) async {
    final controller = AuthSessionController(
      transport: WidgetAuthTransport(),
      store: MemorySessionStore(),
    );

    await tester.pumpWidget(
      MobileAuthBootstrap(
        controller: controller,
        authenticatedAppBuilder: (_) => const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('auth-toggle-mode')));
    await tester.pump();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const Key('auth-display-name')), findsOneWidget);
    expect(find.byKey(const Key('auth-username')), findsOneWidget);
  });
}
