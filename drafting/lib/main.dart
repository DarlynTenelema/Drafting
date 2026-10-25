import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'core/services/api_client.dart';
void main() async {
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await MobileAds.instance.initialize();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('🔴 [Crashlytics Simulador] Error atrapado por FlutterError: ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('🔴 [Crashlytics Simulador] Error silencioso atrapado: $error');
      return true; // Previene que la app crashee o se ponga gris
    };

    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? '373092520666-n6h8cn0tpllr3tacqu2vh4o2efnjf8v9.apps.googleusercontent.com' : null,
      serverClientId: '373092520666-n6h8cn0tpllr3tacqu2vh4o2efnjf8v9.apps.googleusercontent.com',
    );

    // Pre-calentar el backend en segundo plano para evitar Cold Starts
    try {
      ApiClient.get('/').then((_) {}, onError: (_) {});
    } catch (_) {}

    runApp(const DraftingApp());
  }, (error, stack) {
    debugPrint('🔴 [Crashlytics Simulador] Error asíncrono atrapado en la Zona: $error');
  });
}

class DraftingApp extends StatelessWidget {
  const DraftingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Draft',
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
