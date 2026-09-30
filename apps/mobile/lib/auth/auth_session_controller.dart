import 'dart:convert';

import 'auth_models.dart';
import 'auth_session_store.dart';
import 'auth_transport.dart';

enum AuthSessionState {
  signedOut,
  restoring,
  authenticated,
}

class AuthSessionController {
  AuthSessionController({
    required AuthTransport transport,
    required AuthSessionStore store,
  })  : _transport = transport,
        _store = store;

  final AuthTransport _transport;
  final AuthSessionStore _store;

  String? _accessToken;
  AuthSessionState _state = AuthSessionState.signedOut;

  AuthSessionState get state => _state;
  bool get isAuthenticated => _accessToken != null;

  String? get currentUserId {
    final token = _accessToken;
    if (token == null) return null;

    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final json = jsonDecode(payload);
      if (json is! Map) return null;
      return json['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> accessToken() async => _accessToken;

  Future<bool> restore() async {
    _state = AuthSessionState.restoring;
    final refreshToken = await _store.readRefreshToken();

    if (refreshToken == null || refreshToken.isEmpty) {
      _accessToken = null;
      _state = AuthSessionState.signedOut;
      return false;
    }

    try {
      final tokens = await _transport.refresh(refreshToken);
      await _acceptTokens(tokens);
      return true;
    } on AuthTransportException catch (error) {
      _accessToken = null;
      _state = AuthSessionState.signedOut;

      if (error.isUnauthorized) {
        await _store.clearRefreshToken();
      }
      rethrow;
    } catch (_) {
      _accessToken = null;
      _state = AuthSessionState.signedOut;
      rethrow;
    }
  }

  Future<void> login(LoginCredentials credentials) async {
    final tokens = await _transport.login(credentials);
    await _acceptTokens(tokens);
  }

  Future<void> register(RegisterCredentials credentials) async {
    final tokens = await _transport.register(credentials);
    await _acceptTokens(tokens);
  }

  Future<void> refresh() async {
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      _accessToken = null;
      _state = AuthSessionState.signedOut;
      throw const AuthTransportException(
        statusCode: 401,
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Refresh token is unavailable',
      );
    }

    try {
      final tokens = await _transport.refresh(refreshToken);
      await _acceptTokens(tokens);
    } on AuthTransportException catch (error) {
      if (error.isUnauthorized) {
        _accessToken = null;
        _state = AuthSessionState.signedOut;
        await _store.clearRefreshToken();
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final accessToken = _accessToken;

    try {
      if (accessToken != null) {
        await _transport.logout(accessToken);
      }
    } finally {
      _accessToken = null;
      _state = AuthSessionState.signedOut;
      await _store.clearRefreshToken();
    }
  }

  Future<void> _acceptTokens(AuthTokens tokens) async {
    // The server rotates refresh tokens. Persist the replacement before
    // exposing the new access token so app termination cannot leave an
    // already-consumed refresh token on disk.
    await _store.writeRefreshToken(tokens.refreshToken);
    _accessToken = tokens.accessToken;
    _state = AuthSessionState.authenticated;
  }
}
