import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/services/api_client.dart';
import '../core/services/session_service.dart';
import '../core/services/finance_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_screen.dart';

class AppealScreen extends StatefulWidget {
  final String sessionToken;
  const AppealScreen({super.key, required this.sessionToken});

  @override
  State<AppealScreen> createState() => _AppealScreenState();
}

class _AppealScreenState extends State<AppealScreen> {
  final _messageController = TextEditingController();
  bool _isLoading = false;
  bool _submitted = false;

  Future<void> _submitAppeal() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, escribe tu apelación.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.post(
        '/api/v1/support/appeal',
        body: {'message': msg},
      );

      if (response.statusCode == 201) {
        setState(() {
          _submitted = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de conexión: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    try { await GoogleSignIn.instance.disconnect(); } catch (_) {}
    await GoogleSignIn.instance.signOut();
    await SessionService.clearSession();
    FinanceService().reset();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900, // Bloqueo rojo
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.white),
              const SizedBox(height: 24),
              Text(
                'CUENTA EN RIESGO DE BANEO',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Has acumulado demasiadas infracciones. Tu cuenta será baneada permanentemente en los próximos 7 días si no presentas una apelación válida.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16),
              ),
              const SizedBox(height: 32),

              if (_submitted) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Tu apelación ha sido enviada. Los administradores revisarán tu caso. Vuelve a intentar entrar más tarde.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _messageController,
                  maxLines: 5,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Explica por qué no deberíamos banear tu cuenta...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitAppeal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Enviar Apelación', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: _handleLogout,
                child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
