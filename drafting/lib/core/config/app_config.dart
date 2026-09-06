/// Central API configuration for the Flutter app.
///
/// Override at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080
///   flutter build apk --release --dart-define=API_BASE_URL=https://api.tudominio.com
class AppConfig {
  AppConfig._();

  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://drafting-production-0963.up.railway.app',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ufkoozwxlvlaujziojpe.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVma29vend4bHZsYXVqemlvanBlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg2NDMxMjIsImV4cCI6MjEwNDIxOTEyMn0.5waLwgnU5U9fsCUwWZUWgfiCN8_3zSzL35Iy50unICM',
  );

  static String get apiBaseUrl => _apiBaseUrl.replaceAll(RegExp(r'/+$'), '');

  static Uri apiUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$apiBaseUrl$normalizedPath');
  }
}
