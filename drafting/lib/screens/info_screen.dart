import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 28),
          const SizedBox(width: 12),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String description) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text(
          'Información',
          style: GoogleFonts.outfit(
            color: AppTheme.textLight,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppTheme.textLight),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Sección de Actualizaciones ---
            _buildSectionHeader('Nuevas Actualizaciones', Icons.new_releases_outlined),
            _buildInfoCard(
              'Versión 2.1.0 - Orbe Hextech',
              '• Nuevo diseño 3D para el botón de captura con temática Hextech.\n'
              '• Mejoras en la ventana flotante de Android: Nuevo sistema de arrastre y colores personalizados.\n'
              '• Optimizaciones de rendimiento al analizar la pantalla.',
            ),
            
            const SizedBox(height: 16),
            
            // --- Sección de Ayuda ---
            _buildSectionHeader('¿Cómo funciona?', Icons.help_outline),
            _buildInfoCard(
              '1. Configura tus Roles',
              'Ingresa tu rol principal, secundario y de autofill en la pantalla principal.',
            ),
            _buildInfoCard(
              '2. Activa el Sistema',
              'Presiona el Orbe Hextech para encender el servicio. Aparecerá una ventana flotante con el icono de una cámara.',
            ),
            _buildInfoCard(
              '3. Analiza el Draft',
              'Cuando estés en la fase de selección de campeones, presiona la cámara flotante. La IA analizará a tu equipo y al rival, y te recomendará el mejor campeón para tu rol.',
            ),

            const SizedBox(height: 16),

            // --- Sección Acerca de ---
            _buildSectionHeader('Acerca de Drafting', Icons.info_outline),
            _buildInfoCard(
              'Desarrollado con IA',
              'Drafting utiliza el modelo Gemini 2.5 Flash Lite para visión artificial y análisis de estrategia en tiempo real.',
            ),
            
            const SizedBox(height: 30),
            Center(
              child: Text(
                'Versión 2.1.0',
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
