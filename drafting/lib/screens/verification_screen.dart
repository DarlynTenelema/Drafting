import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/services/api_client.dart';
import '../theme/app_theme.dart';

class VerificationScreen extends StatefulWidget {
  final String channelId;
  const VerificationScreen({super.key, required this.channelId});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _proofController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitVerification() async {
    if (_proofController.text.trim().isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final response = await ApiClient.post(
        '/moderation/verify_identity',
        authenticated: true,
        body: {
          'channel_id': widget.channelId,
          'proof_url': _proofController.text.trim(),
        },
      );
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prueba enviada. El equipo de moderación revisará tu canal pronto.')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al enviar la prueba')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Verificación de Identidad', style: GoogleFonts.outfit(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tu canal de YouTube es muy popular (>10k subs). Por seguridad, necesitamos verificar tu identidad antes de que puedas subir videos.',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Instrucciones:',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Sube un video "Oculto" a tu canal de YouTube o Google Drive donde muestres tu rostro y digas:\n\n"Hola, soy [Tu Nombre] y quiero unirme a la comunidad de creadores de Drafting".\n\nPega el enlace a continuación:',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _proofController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Enlace de prueba (Video MP4 o YouTube)',
                hintText: 'https://...',
                labelStyle: const TextStyle(color: AppTheme.textMuted),
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primary),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitVerification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Enviar para Revisión',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
