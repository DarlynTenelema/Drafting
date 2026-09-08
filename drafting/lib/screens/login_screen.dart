import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/services/api_client.dart';
import '../core/services/session_service.dart';
import '../theme/app_theme.dart';
import 'main_layout.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // En google_sign_in 7.2.0, el ID se pasa al inicializar la instancia
    _googleSignIn.initialize(
      serverClientId: '373092520666-e4ltfq0ed1b3scgcc2v3hj7aqno7rkut.apps.googleusercontent.com',
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Limpieza profunda de sesión para evitar caché de cuentas previas
      try { await _googleSignIn.disconnect(); } catch (_) {}
      try { await _googleSignIn.signOut(); } catch (_) {}

      final googleUser = await _googleSignIn.authenticate();
      if (googleUser == null) {
        throw Exception('canceled'); // User canceled sign in
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
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
              builder: (_) => MainLayoutScreen(sessionToken: sessionToken),
            ),
          );
        } else {
          _showError('Error del servidor (${response.statusCode}): ${response.body}');
          debugPrint('Backend auth error: ${response.statusCode} - ${response.body}');
        }
      } else {
        _showError('No se pudo obtener el token de Google.');
      }
    } on PlatformException catch (e) {
      if (e.code == 'network_error') {
        _showError('No se pudo conectar. Verifica tu internet e inténtalo de nuevo.');
      } else if (e.code != 'sign_in_canceled' && !e.toString().contains('canceled')) {
        _showError('Fallo en Google SignIn: código ${e.code}, mensaje: ${e.message}');
      }
      debugPrint('PlatformException: ${e.toString()}');
    } on ApiException catch (e) {
      _showError(e.message);
      debugPrint('ApiException: ${e.message}');
    } catch (error) {
      if (!error.toString().contains('canceled')) {
        _showError('Excepción inesperada: $error');
      }
      debugPrint('Unexpected error: ${error.toString()}');
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.accent),
            const SizedBox(width: 8),
            Text('¡Ups!', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Entendido', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
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
              const Spacer(flex: 1),
              
              // Botón de Google Principal
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: SizedBox(
                  width: double.infinity,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              
              const Spacer(flex: 1),
              
            ],
          ),
        ),
      ),
    );
  }
}
