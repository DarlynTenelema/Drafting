import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await GoogleSignIn.instance.initialize(
    clientId: kIsWeb ? '373092520666-n6h8cn0tpllr3tacqu2vh4o2efnjf8v9.apps.googleusercontent.com' : null,
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
