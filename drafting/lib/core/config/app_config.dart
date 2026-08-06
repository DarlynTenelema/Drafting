/// Central API configuration for the Flutter app.
///
/// Override at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080
///   flutter build apk --release --dart-define=API_BASE_URL=https://api.tudominio.com
class AppConfig {
  AppConfig._();

  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static String get apiBaseUrl => _apiBaseUrl.replaceAll(RegExp(r'/+$'), '');

  static Uri apiUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$apiBaseUrl$normalizedPath');
  }
}
