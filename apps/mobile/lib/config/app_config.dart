class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
  });

  final String apiBaseUrl;

  static const fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'PULSEMESH_API_URL',
      defaultValue: 'http://10.0.2.2:4000',
    ),
  );
}
