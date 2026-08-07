import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // serverClientId is required in google_sign_in v7+ when google-services.json is not used.
  // This must be the Web OAuth 2.0 Client ID (not the Android one) from Google Cloud Console.
  // The backend uses this same Client ID (GOOGLE_CLIENT_ID env var) to verify the idToken.
  await GoogleSignIn.instance.initialize(
    serverClientId: '373092520666-n6h8cn0tpllr3tacqu2vh4o2efnjf8v9.apps.googleusercontent.com',
  );
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
