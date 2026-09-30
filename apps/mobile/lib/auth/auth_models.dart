class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final accessToken = json['accessToken'] as String?;
    final refreshToken = json['refreshToken'] as String?;

    if (accessToken == null || accessToken.isEmpty) {
      throw const FormatException('Missing access token');
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const FormatException('Missing refresh token');
    }

    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }
}

class LoginCredentials {
  const LoginCredentials({
    required this.email,
    required this.password,
    this.device,
    this.browser,
    this.os,
  });

  final String email;
  final String password;
  final String? device;
  final String? browser;
  final String? os;

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        if (device != null) 'device': device,
        if (browser != null) 'browser': browser,
        if (os != null) 'os': os,
      };
}

class RegisterCredentials {
  const RegisterCredentials({
    required this.email,
    required this.password,
    required this.username,
    required this.displayName,
    this.device,
    this.browser,
    this.os,
  });

  final String email;
  final String password;
  final String username;
  final String displayName;
  final String? device;
  final String? browser;
  final String? os;

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'username': username,
        'displayName': displayName,
        if (device != null) 'device': device,
        if (browser != null) 'browser': browser,
        if (os != null) 'os': os,
      };
}
