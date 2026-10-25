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
  static const _deviceIdKey = 'app_device_id';

  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
      deviceId = 'dev_${now}_${DateTime.now().millisecond.toRadixString(16)}';
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }
}
