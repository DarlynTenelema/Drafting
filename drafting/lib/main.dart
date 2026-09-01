import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher, FlutterError, FlutterErrorDetails;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'core/state/active_product_state.dart';
import 'core/config/app_config.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('🔴 [Crashlytics Simulador] Error atrapado por FlutterError: ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('🔴 [Crashlytics Simulador] Error silencioso atrapado: $error');
      return true; // Previene que la app crashee o se ponga gris
    };

    // Inicializar Supabase si la llave anónima está configurada
    if (AppConfig.supabaseAnonKey.isNotEmpty) {
      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
        );
        debugPrint("Supabase inicializado correctamente.");
      } catch (e) {
        debugPrint("Advertencia: Supabase initialization failed: $e");
      }
    } else {
      debugPrint("Advertencia: SUPABASE_ANON_KEY no está definida. La subida de archivos fallará.");
    }

    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? '373092520666-n6h8cn0tpllr3tacqu2vh4o2efnjf8v9.apps.googleusercontent.com' : null,
      serverClientId: '373092520666-n6h8cn0tpllr3tacqu2vh4o2efnjf8v9.apps.googleusercontent.com',
    );

    await ActiveProductState().init();

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
