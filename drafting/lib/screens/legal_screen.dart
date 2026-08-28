import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Términos y Condiciones',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Condiciones para Emprendedores y Creadores',
              style: GoogleFonts.outfit(
                color: AppTheme.primary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Drafting ofrece a los usuarios la posibilidad de crear modelos de Inteligencia Artificial ("Grupos" u "OTPs") y monetizarlos. Al adquirir un plan de emprendedor, aceptas el siguiente modelo de distribución de ingresos y costos asociados:',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            _buildClause(
              'Comisiones de Terceros',
              'Todas las transacciones generadas por la venta de tus suscripciones a consumidores están sujetas a una retención fija del 15% por parte de Google Play Store.',
            ),
            _buildClause(
              'Distribución de Ganancias',
              'Del saldo restante (post-Google Play), las ganancias se dividirán porcentualmente entre Drafting y el Creador, según la tarifa de entrada adquirida (Ej. 50%/50%, 60%/40%).',
            ),
            _buildClause(
              'Costos de Inteligencia Artificial (API)',
              'Para garantizar la sostenibilidad, el costo exacto del consumo de la API generado por tus consumidores se deducirá exclusivamente de tu porcentaje de ganancia.',
            ),
            _buildClause(
              'Retiros (Payouts)',
              'Los fondos generados solo podrán ser retirados mediante Stripe Connect Express una vez alcanzado el mínimo de \$100 USD. Las comisiones por retiro de Stripe serán deducidas de tus fondos.',
            ),
            const SizedBox(height: 32),
            const Divider(color: Colors.white24),
            const SizedBox(height: 32),
            Text(
              'Términos Generales de Uso',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Al acceder y utilizar la aplicación Drafting, aceptas estar sujeto a estas Condiciones del Servicio y a todas las leyes y regulaciones aplicables. Eres responsable de mantener la confidencialidad de tu cuenta de Google. Los materiales se proporcionan "tal cual", sin garantías expresas o implícitas.',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(true); // Return true indicating it was read
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Entendido, volver'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildClause(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: AppTheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
