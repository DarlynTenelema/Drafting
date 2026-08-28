import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class NativeService {
  static const MethodChannel _channel = MethodChannel('com.drafting.app/capture');
  static const EventChannel _eventChannel = EventChannel('com.drafting.app/events');

  static Stream<Map<dynamic, dynamic>> get onEvent {
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      return event as Map<dynamic, dynamic>;
    });
  }

  static Future<bool> startCaptureService({
    required String baseUrl,
    required String sessionToken,
    required String mainRole,
    required String secondaryRole,
    required String autofillRole,
    required bool isPremium,
    required String otpChampions,
    required String? activeCreatorId,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('startService', {
        'baseUrl': baseUrl,
        'sessionToken': sessionToken,
        'mainRole': mainRole,
        'secondaryRole': secondaryRole,
        'autofillRole': autofillRole,
        'isPremium': isPremium,
        'otpChampions': otpChampions,
        'activeCreatorId': activeCreatorId ?? '',
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint("Failed to start service: '${e.message}'.");
      return false;
    }
  }

  static Future<void> stopCaptureService() async {
    try {
      await _channel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop service: '${e.message}'.");
    }
  }
}
