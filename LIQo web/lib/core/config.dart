/// Build-time configuration.
///
/// Run with `--dart-define=API_BASE=https://api.example.com` to point the app
/// at another backend. Without it the app talks to the local dev server.
///
/// The internal deployment (owner decision 2026-10-23, until a domain gives the
/// server a fixed address) builds with `--dart-define=API_CONFIG_URL=/config/api.json`
/// instead: the app reads the server's current address from that file on the
/// web app's own fixed address when it opens (`core/api_address.dart`).
class AppConfig {
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:3000',
  );

  /// Where to read the server's current address (empty: use [apiBase]).
  static const String apiConfigUrl = String.fromEnvironment('API_CONFIG_URL');

  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.1.0-dev',
  );
}
