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
    required String planTier,
    required String otpChampions,
    required String? activeCreatorId,
    String language = 'es',
  }) async {
    try {
      final bool result = await _channel.invokeMethod('startService', {
        'baseUrl': baseUrl,
        'sessionToken': sessionToken,
        'mainRole': mainRole,
        'secondaryRole': secondaryRole,
        'autofillRole': autofillRole,
        'isPremium': isPremium,
        'planTier': planTier,
        'otpChampions': otpChampions,
        'activeCreatorId': activeCreatorId ?? '',
        'language': language,
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

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final bool? isIgnoring = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return isIgnoring ?? true;
    } on PlatformException catch (e) {
      debugPrint("Failed to check battery optimization: '${e.message}'.");
      return true;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final bool? requested = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return requested ?? false;
    } on PlatformException catch (e) {
      debugPrint("Failed to request battery optimization exemption: '${e.message}'.");
      return false;
    }
  }

  /// Obtiene la versión instalada del paquete directamente desde Android PackageManager
  static Future<Map<String, dynamic>> getAppVersion() async {
    try {
      final Map<dynamic, dynamic>? res = await _channel.invokeMethod('getAppVersion');
      if (res != null) {
        return {
          'versionCode': (res['versionCode'] is int) ? res['versionCode'] as int : 38,
          'versionName': (res['versionName'] ?? '1.0.6').toString(),
          'packageName': (res['packageName'] ?? 'com.drafting.app').toString(),
        };
      }
    } catch (e) {
      debugPrint("Failed to get app version: $e");
    }
    return {
      'versionCode': 38,
      'versionName': '1.0.6',
      'packageName': 'com.drafting.app',
    };
  }

  /// Consulta directamente a Google Play In-App Updates API si hay actualización o descarga en segundo plano
  static Future<Map<String, dynamic>> checkPlayInAppUpdate() async {
    try {
      final Map<dynamic, dynamic>? res = await _channel.invokeMethod('checkPlayInAppUpdate');
      if (res != null) {
        return {
          'updateAvailable': res['updateAvailable'] == true,
          'availableVersionCode': (res['availableVersionCode'] is int) ? res['availableVersionCode'] as int : 0,
          'flexibleAllowed': res['flexibleAllowed'] == true,
          'immediateAllowed': res['immediateAllowed'] == true,
          'installStatus': (res['installStatus'] is int) ? res['installStatus'] as int : 0,
          'isDownloaded': res['isDownloaded'] == true,
        };
      }
    } catch (e) {
      debugPrint("Failed to check Play In-App Update: $e");
    }
    return {
      'updateAvailable': false,
      'availableVersionCode': 0,
      'flexibleAllowed': false,
      'immediateAllowed': false,
      'installStatus': 0,
      'isDownloaded': false,
    };
  }

  /// Inicia la actualización nativa dentro de la app (Google Play In-App Updates: Flexible en 2do plano o Immediate)
  static Future<Map<String, dynamic>> startInAppUpdate({
    String mode = 'flexible',
    bool openStoreFallback = true,
    String? fallbackUrl,
  }) async {
    try {
      final Map<dynamic, dynamic>? res = await _channel.invokeMethod('startInAppUpdate', {
        'mode': mode,
        'openStoreFallback': openStoreFallback,
        'url': fallbackUrl ?? 'https://play.google.com/store/apps/details?id=com.drafting.app',
      });
      if (res != null) {
        return {
          'started': res['started'] == true,
          'method': (res['method'] ?? 'none').toString(),
        };
      }
    } catch (e) {
      debugPrint("Failed to start In-App Update: $e");
    }
    return {'started': false, 'method': 'none'};
  }

  /// Aplica e instala de inmediato la actualización ya descargada en segundo plano por Google Play
  static Future<bool> completeInAppUpdate() async {
    try {
      final bool? completed = await _channel.invokeMethod<bool>('completeInAppUpdate');
      return completed ?? false;
    } catch (e) {
      debugPrint("Failed to complete In-App Update: $e");
      return false;
    }
  }

  /// Abre directamente la ficha de actualización de Drafting en Google Play Store (con 1 clic)
  static Future<bool> openPlayStoreUpdate({String? fallbackUrl}) async {
    try {
      final bool? opened = await _channel.invokeMethod<bool>('openPlayStoreUpdate', {
        'url': fallbackUrl ?? 'https://play.google.com/store/apps/details?id=com.drafting.app',
      });
      return opened ?? false;
    } catch (e) {
      debugPrint("Failed to open Play Store update: $e");
      return false;
    }
  }

  /// Abre cualquier URL de redes sociales, transmisión en vivo o evento en la app nativa correspondiente
  static Future<bool> openExternalUrl(String url) async {
    try {
      final bool? launched = await _channel.invokeMethod<bool>('openExternalUrl', {
        'url': url,
      });
      return launched ?? false;
    } catch (e) {
      debugPrint("Failed to open external URL ($url): $e");
      return false;
    }
  }

  /// Verifica si las notificaciones del sistema están activas para la app
  static Future<bool> areNotificationsEnabled() async {
    try {
      final bool? enabled = await _channel.invokeMethod<bool>('areNotificationsEnabled');
      return enabled ?? false;
    } catch (e) {
      debugPrint("Failed to check notification status: $e");
      return false;
    }
  }

  /// Solicita permiso de notificaciones con 1 clic en Android 13+ o abre el ajuste directo de la app
  static Future<bool> requestNotificationPermission() async {
    try {
      final bool? requested = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return requested ?? false;
    } catch (e) {
      debugPrint("Failed to request notification permission: $e");
      return false;
    }
  }

  /// Sincroniza el idioma activo con las preferencias nativas de la burbuja flotante
  static Future<void> setNativeLanguage(String languageCode) async {
    try {
      await _channel.invokeMethod('setLanguage', {
        'language': languageCode,
      });
    } catch (e) {
      debugPrint("Failed to set native language: $e");
    }
  }

  /// Muestra una notificación nativa de alta prioridad cuando hay un nuevo directo o evento activo
  static Future<void> showEventNotification({
    required String title,
    required String body,
    String url = '',
  }) async {
    try {
      await _channel.invokeMethod('showEventNotification', {
        'title': title,
        'body': body,
        'url': url,
      });
    } catch (e) {
      debugPrint("Failed to show native event notification: $e");
    }
  }
}
