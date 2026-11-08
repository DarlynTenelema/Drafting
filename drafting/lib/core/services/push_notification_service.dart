import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Si la notificación contiene un evento o directo y no vino con display automático
  final data = message.data;
  final title = message.notification?.title ?? data['title'] ?? '🔴 ¡Drafting está en Directo!';
  final body = message.notification?.body ?? data['subtitle'] ?? data['body'] ?? 'Toca para unirte ahora mismo.';
  final actionUrl = (data['action_url'] ?? data['url'] ?? '').toString();

  if (message.notification == null && (title.isNotEmpty || body.isNotEmpty)) {
    await NativeService.showEventNotification(
      title: title,
      body: body,
      url: actionUrl,
    );
  }
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const String topicLiveEvents = 'live_events';
  static const String topicAllUsers = 'all_users';

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Manejar mensajes en primer plano (foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final data = message.data;
        final title = message.notification?.title ?? data['title'] ?? '🔴 ¡Drafting está en Directo!';
        final body = message.notification?.body ?? data['subtitle'] ?? data['body'] ?? 'Toca para unirte a la transmisión.';
        final actionUrl = (data['action_url'] ?? data['url'] ?? '').toString();

        NativeService.showEventNotification(
          title: title,
          body: body,
          url: actionUrl,
        );
      });

      // Manejar clic en la notificación cuando la app estaba en segundo plano
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleNotificationClick(message);
      });

      // Manejar apertura si la app estaba completamente terminada (arranque en frío)
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationClick(initialMessage);
      }

      // Si el usuario ya tenía las notificaciones habilitadas, asegurar suscripción a tópicos
      final prefs = await SharedPreferences.getInstance();
      final hasEnabled = prefs.getBool('notifications_push_enabled') ?? true;
      if (hasEnabled) {
        await _subscribeToTopicsSilently();
      }

      _initialized = true;
    } catch (e) {
      debugPrint('⚠️ PushNotificationService initialize: $e');
    }
  }

  void _handleNotificationClick(RemoteMessage message) {
    final data = message.data;
    final actionUrl = (data['action_url'] ?? data['url'] ?? '').toString().trim();
    if (actionUrl.isNotEmpty) {
      NativeService.openExternalUrl(actionUrl);
    }
  }

  Future<void> _subscribeToTopicsSilently() async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topicLiveEvents);
      await FirebaseMessaging.instance.subscribeToTopic(topicAllUsers);
    } catch (_) {}
  }

  /// Activa las notificaciones con 1 clic solicitando permisos y suscribiendo al tópico de directos
  Future<bool> enableLiveNotifications() async {
    try {
      await Firebase.initializeApp();
      // Solicitar permiso en Android 13+ y iOS
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      final isAuthorized = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      // También invocar el permiso nativo por si Android necesita activar canales del sistema
      await NativeService.requestNotificationPermission();

      await FirebaseMessaging.instance.subscribeToTopic(topicLiveEvents);
      await FirebaseMessaging.instance.subscribeToTopic(topicAllUsers);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_push_enabled', true);
      await prefs.setBool('has_shown_events_notif_modal', true);

      return isAuthorized;
    } catch (e) {
      debugPrint('Error habilitando notificaciones push: $e');
      return false;
    }
  }

  Future<void> disableLiveNotifications() async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topicLiveEvents);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_push_enabled', false);
    } catch (_) {}
  }

  Future<bool> isLiveNotificationEnabled() async {
    try {
      final nativeEnabled = await NativeService.areNotificationsEnabled();
      if (!nativeEnabled) return false;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('notifications_push_enabled') ?? true;
    } catch (_) {
      return true;
    }
  }
}

