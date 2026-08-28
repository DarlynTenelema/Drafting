import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/services/api_client.dart';
import '../theme/app_theme.dart';

class ReportDialog extends StatefulWidget {
  final String videoId;
  const ReportDialog({super.key, required this.videoId});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String? _selectedReason;
  final _proofController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _reasons = [
    'Falsificación de identidad / Robo de contenido',
    'Contenido de odio o violencia',
    'Contenido para adultos disfrazado (Bypass de IA)',
  ];

  Future<void> _submitReport() async {
    if (_selectedReason == null) return;
    
    // If identity theft is selected, require proof
    if (_selectedReason == _reasons[0] && _proofController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor incluye un enlace para probar tu identidad.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await ApiClient.post(
        '/moderation/report',
        authenticated: true,
        body: {
          'video_id': widget.videoId,
          'reason': _selectedReason,
          'proof_url': _proofController.text.trim(),
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reporte enviado. Nuestro equipo lo revisará pronto.'), backgroundColor: Colors.green),
          );
          Navigator.pop(context); // Close dialog
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al enviar el reporte.'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Reportar Video', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Cuál es el problema con este video?', style: GoogleFonts.inter(color: Colors.white70)),
            const SizedBox(height: 16),
            ..._reasons.map((reason) {
              return RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.primary,
                title: Text(reason, style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
                value: reason,
                groupValue: _selectedReason,
                onChanged: (value) {
                  setState(() {
                    _selectedReason = value;
                  });
                },
              );
            }),
            if (_selectedReason == _reasons[0]) ...[
              const SizedBox(height: 16),
              Text('Enlace de prueba de identidad', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _proofController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ej. Enlace a tu canal oficial...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted),
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: AppTheme.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _isSubmitting || _selectedReason == null ? null : _submitReport,
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Enviar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
