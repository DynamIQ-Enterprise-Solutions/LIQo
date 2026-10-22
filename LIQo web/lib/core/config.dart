/// Build-time configuration.
///
/// Run with `--dart-define=API_BASE=https://api.example.com` to point the app
/// at another backend. Without it the app talks to the local dev server.
class AppConfig {
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:3000',
  );

  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0-dev',
  );
}
