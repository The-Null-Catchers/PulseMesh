class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.realtimeWebSocketUrl,
  });

  final String apiBaseUrl;
  final String realtimeWebSocketUrl;

  static const fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'PULSEMESH_API_URL',
      defaultValue: 'http://10.0.2.2:4000',
    ),
    realtimeWebSocketUrl: String.fromEnvironment(
      'PULSEMESH_WS_URL',
      defaultValue: 'ws://10.0.2.2:4000/realtime',
    ),
  );
}
