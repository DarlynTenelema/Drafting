import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'core/services/ad_service.dart';
import 'core/services/api_client.dart';
import 'core/services/iap_service.dart';

void main() async {
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Habilitar modo Edge-to-Edge requerido por Android 15+ (SDK 35+)
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('🔴 [Crashlytics Simulador] Error atrapado por FlutterError: ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('🔴 [Crashlytics Simulador] Error silencioso atrapado: $error');
      return true; // Previene que la app crashee o se ponga gris
    };

    // Renderizar la UI de inmediato para evitar bloqueos o ANR en el arranque
    runApp(const DraftingApp());

    // Inicializar servicios nativos después del primer frame cuando MainActivity ya está lista
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeBackgroundServices();
    });
  }, (error, stack) {
    debugPrint('🔴 [Crashlytics Simulador] Error asíncrono atrapado en la Zona: $error');
  });
}

Future<void> _initializeBackgroundServices() async {
  // 1. Inicializar Google Sign-In de forma segura
  try {
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? '373092520666-e4ltfq0ed1b3scgcc2v3hj7aqno7rkut.apps.googleusercontent.com' : null,
      serverClientId: '373092520666-e4ltfq0ed1b3scgcc2v3hj7aqno7rkut.apps.googleusercontent.com',
    );
  } catch (e) {
    debugPrint('⚠️ Error inicializando GoogleSignIn: $e');
  }

  // 2. Inicializar pasarela de compras Google Play Billing
  try {
    unawaited(InAppPurchaseService.instance.initialize());
  } catch (_) {}

  // 3. Pre-calentar el backend en segundo plano para evitar Cold Starts
  try {
    ApiClient.get('/').then((_) {}, onError: (_) {});
  } catch (_) {}

  // 4. Inicializar Appodeal con un breve retraso para asegurar que la Activity esté activa
  try {
    await Future.delayed(const Duration(milliseconds: 600));
    await AdService.initialize();
  } catch (_) {}
}

class DraftingApp extends StatelessWidget {
  const DraftingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Draft',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
