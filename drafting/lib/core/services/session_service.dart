import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  SessionService._();

  static const _sessionTokenKey = 'session_token';

  static Future<String?> getSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionTokenKey);
  }

  static Future<void> saveSessionToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionTokenKey, token);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenKey);
  }

  static Future<bool> hasSession() async {
    final token = await getSessionToken();
    return token != null && token.isNotEmpty;
  }
}
