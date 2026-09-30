class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
  });

  final String apiBaseUrl;

  String get realtimeWebSocketUrl {
    final api = Uri.parse(apiBaseUrl);
    return api
        .replace(
          scheme: api.scheme == 'https' ? 'wss' : 'ws',
          path: '/realtime',
          query: null,
          fragment: null,
        )
        .toString();
  }

  static const fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'PULSEMESH_API_URL',
      defaultValue: 'http://10.0.2.2:4000',
    ),
  );
}
