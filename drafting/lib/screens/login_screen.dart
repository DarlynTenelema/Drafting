import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/services/api_client.dart';
import '../core/services/session_service.dart';
import '../theme/app_theme.dart';
import 'index_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final googleUser = await _googleSignIn.authenticate(scopeHint: ['email']);
      if (googleUser == null) {
        setState(() { _isLoading = false; });
        return;
      }

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      // Google API sends an idToken when authenticated
      final String? idToken = googleAuth.idToken; 

      if (idToken != null) {
        final response = await ApiClient.post(
          '/api/v1/auth/google',
          body: {'google_token': idToken},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final sessionToken = data['session_token'] as String;

          await SessionService.saveSessionToken(sessionToken);

          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => IndexScreen(sessionToken: sessionToken),
            ),
          );
        } else {
          _showError('Error en el servidor al autenticar.');
        }
      } else {
        _showError('No se pudo obtener el token de Google.');
      }
    } catch (error) {
      _showError('Ocurrió un error al iniciar sesión.');
      debugPrint(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showUpdatesInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Pantalla de nuevas actualizaciones próximamente'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.background,
              AppTheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // Título "Drafting"
              Text(
                'Drafting',
                style: GoogleFonts.outfit(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textLight,
                  letterSpacing: 2.0,
                  shadows: [
                    Shadow(
                      color: AppTheme.primary.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tus mejores picks, al instante.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppTheme.textMuted,
                ),
              ),
              const Spacer(flex: 2),
              // Botón de Google
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: _isLoading
                    ? const CircularProgressIndicator(color: AppTheme.primary)
                    : ElevatedButton(
                        onPressed: _handleGoogleSignIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 8,
                          shadowColor: AppTheme.primary.withValues(alpha: 0.3),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'icon/google.img',
                              height: 24,
                              width: 24,
                              errorBuilder: (context, error, stackTrace) => 
                                const Icon(Icons.g_mobiledata, size: 36, color: Colors.blue),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Continuar con Google',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const Spacer(flex: 1),
              // Botón de Info (!)
              IconButton(
                onPressed: _showUpdatesInfo,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5), width: 2),
                  ),
                  child: const Icon(
                    Icons.priority_high,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
