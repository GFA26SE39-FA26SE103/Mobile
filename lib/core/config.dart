/// Build-time configuration, set with `--dart-define`.
///
/// The default is the shared dev API, the same backend the web app uses.
/// `flutter run --dart-define=API_URL=http://10.0.2.2:5080` points the Android
/// emulator at a backend running on the host instead.
class AppConfig {
  const AppConfig._();

  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://supermarket-api-dev.kitsuracloud.com');

  /// Signs in against the in-app demo backend instead of `/api/auth/login`.
  static const mockAuth = bool.fromEnvironment('MOCK_AUTH');

  /// Runs shifts, task offers, tasks, alerts and swaps on the in-app demo backend instead of
  /// the API (`--dart-define=DEMO_OPS=true`). Demo sign-in always uses it, since its token is
  /// not valid on a server. Staff reports stay in-app either way until the API has them.
  static const demoOperations = mockAuth || bool.fromEnvironment('DEMO_OPS');
}
