import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'my_tickets_screen.dart';
import 'create_ticket_screen.dart';
import 'suggestion_box_screen.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Centro de Ayuda', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),
          Text(
            '¿En qué podemos ayudarte?',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Encuentra soluciones rápidas o contacta con nuestro equipo de soporte.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 32),
          
          _buildActionCard(
            context: context,
            title: 'Crear Nuevo Reporte',
            subtitle: 'Reporta un bug, fraude o problema de cuenta.',
            icon: Icons.report_problem,
            color: Colors.orangeAccent,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateTicketScreen()));
            },
          ),
          const SizedBox(height: 16),
          
          _buildActionCard(
            context: context,
            title: 'Mis Reportes Activos',
            subtitle: 'Revisa el estado y responde a tus tickets actuales.',
            icon: Icons.receipt_long,
            color: Colors.blueAccent,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTicketsScreen()));
            },
          ),
          const SizedBox(height: 16),
          
          _buildActionCard(
            context: context,
            title: 'Buzón de Ideas',
            subtitle: 'Sugiere nuevas funciones o mejoras para la app.',
            icon: Icons.lightbulb,
            color: Colors.yellowAccent,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SuggestionBoxScreen()));
            },
          ),
          
          const SizedBox(height: 40),
          Text(
            'Preguntas Frecuentes',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          _buildFAQItem(
            question: '¿Cuánto tiempo tarda en responder soporte?',
            answer: 'Normalmente nuestro equipo de moderadores responde en menos de 24 horas hábiles.',
          ),
          _buildFAQItem(
            question: 'Me han rechazado un retiro, ¿qué hago?',
            answer: 'Verifica en la sección de finanzas el motivo exacto (suele ser datos bancarios erróneos). Si persiste, abre un reporte.',
          ),
          _buildFAQItem(
            question: '¿Cómo funciona el baneo por strikes?',
            answer: 'Si acumulas 5 strikes por violar las normas (contenido inapropiado o fraude), tu cuenta entrará en riesgo de baneo permanente. Podrás apelar en la pantalla emergente.',
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white30),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQItem({required String question, required String answer}) {
    return Theme(
      data: ThemeData.dark().copyWith(
        dividerColor: Colors.transparent,
      ),
      child: ExpansionTile(
        title: Text(question, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
        collapsedIconColor: Colors.white54,
        iconColor: AppTheme.primary,
        childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        children: [
          Text(answer, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}
