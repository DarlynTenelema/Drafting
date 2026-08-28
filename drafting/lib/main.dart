import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'core/state/active_product_state.dart';
import 'core/config/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  
  // Inicializar Firebase y Crashlytics para reporte de errores en producción
  try {
    await Firebase.initializeApp();
    if (!kIsWeb) {
      // Capturar errores de Flutter (UI)
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      // Capturar errores asíncronos que no captura FlutterError
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  } catch (e) {
    debugPrint("Advertencia: Firebase initialization failed: $e");
  }

  await GoogleSignIn.instance.initialize(
    clientId: kIsWeb ? '373092520666-n6h8cn0tpllr3tacqu2vh4o2efnjf8v9.apps.googleusercontent.com' : null,
    serverClientId: '373092520666-n6h8cn0tpllr3tacqu2vh4o2efnjf8v9.apps.googleusercontent.com',
  );

  await ActiveProductState().init();

  runApp(const DraftingApp());
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
