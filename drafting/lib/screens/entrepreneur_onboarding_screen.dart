import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'entrepreneur_dashboard_screen.dart';
import 'calculator_screen.dart';
import 'legal_screen.dart';
import 'group_setup_screen.dart';
import 'leaderboard_screen.dart';

class EntrepreneurOnboardingScreen extends StatefulWidget {
  const EntrepreneurOnboardingScreen({super.key});

  @override
  State<EntrepreneurOnboardingScreen> createState() => _EntrepreneurOnboardingScreenState();
}

class _EntrepreneurOnboardingScreenState extends State<EntrepreneurOnboardingScreen> {
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Planes para Emprender',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'dashboard',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EntrepreneurDashboardScreen()));
            },
            backgroundColor: Colors.cyan,
            icon: const Icon(Icons.dashboard, color: Colors.white),
            label: const Text('Mi Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'leaderboard',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
            },
            backgroundColor: AppTheme.primary,
            child: const Icon(Icons.leaderboard, color: Colors.white),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'calculator',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CalculatorScreen()));
            },
            backgroundColor: AppTheme.primary,
            child: const Icon(Icons.calculate, color: Colors.white),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text(
            'Modelos Individuales (OTP)',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Perfecto si eres experto en un solo campeón.',
            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _buildPlanCard(
            'OTP Básico', '50%', 10, 'mes',
            availableSlots: 100,
            features: [
              'Empieza tu emprendimiento sin riesgo',
              '50% de ganancia por cada suscriptor',
              'Límite de 100 usuarios mensuales',
              'Sin costos de infraestructura cloud',
            ],
          ),
          _buildPlanCard(
            'OTP Pro', '70%', 30, 'mes',
            availableSlots: 45,
            features: [
              'Maximiza tus ingresos como experto',
              '70% de ganancia por cada suscriptor',
              'Límite de 300 usuarios mensuales',
              'Insignia de "Creador Pro" en Leaderboard',
              'Soporte prioritario para tu IA',
            ],
          ),
          _buildPlanCard(
            'OTP Leyenda', '90%', 50, 'mes',
            availableSlots: 0,
            features: [
              'Conviértete en una leyenda de Drafting',
              '90% de ganancia (la comisión máxima)',
              'Límite de 500 usuarios mensuales',
              'Destacado automático en la tienda',
              'Acceso anticipado a nuevas funciones',
            ],
          ),
          
          const SizedBox(height: 32),
          
          Text(
            'Modelos de Grupo (Equipos)',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Entrena modelos generales con tu organización.',
            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _buildPlanCard(
            'Grupo Start', '50%', 100, 'mes',
            isGroup: true,
            availableSlots: 12,
            features: [
              'Ideal para academias y equipos amateur',
              '50% de ganancias distribuidas',
              'Límite de 1,000 suscriptores',
              'Entrena IAs para los 5 roles del juego',
              'Panel de control para múltiples analistas',
            ],
          ),
          _buildPlanCard(
            'Grupo Avanzado', '70%', 300, 'mes',
            isGroup: true,
            availableSlots: 0,
            features: [
              'Para organizaciones en crecimiento',
              '70% de ganancias para tu equipo',
              'Límite de 3,000 suscriptores',
              'Perfil de equipo verificado con logo',
              'Herramientas de análisis de rendimiento',
              'Algoritmo de recomendación prioritario',
            ],
          ),
          _buildPlanCard(
            'Grupo Elite', '90%', 500, 'mes',
            isGroup: true,
            availableSlots: 2,
            features: [
              'El plan definitivo para equipos Tier 1',
              '90% de ganancia (máxima rentabilidad)',
              'Límite masivo de 5,000 suscriptores',
              'Promoción destacada en la app principal',
              'Monetización global sin restricciones',
              'Insignia dorada de "Equipo Elite"',
              'Soporte VIP 24/7 con ingenieros',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(String name, String percentage, double price, String period, {bool isGroup = false, int availableSlots = 100, List<String> features = const []}) {
    bool isPremium = name.contains('Leyenda') || name.contains('Elite');
    bool isPro = name.contains('Pro') || name.contains('Avanzado');
    bool isFull = availableSlots == 0;
    
    // Aesthetic colors
    Color borderColor = Colors.white.withValues(alpha: 0.05);
    Color tagColor = AppTheme.primary;
    List<Color> gradientColors = [
      AppTheme.surface,
      AppTheme.surface,
    ];

    if (isPremium) {
      borderColor = const Color(0xFFFFD700).withValues(alpha: 0.5); // Gold
      tagColor = const Color(0xFFFFD700);
      gradientColors = [
        const Color(0xFFFFD700).withValues(alpha: 0.1),
        AppTheme.surface,
      ];
    } else if (isPro) {
      borderColor = const Color(0xFF00E5FF).withValues(alpha: 0.3); // Cyan/Silver
      tagColor = const Color(0xFF00E5FF);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: isPremium
            ? [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: tagColor.withValues(alpha: 0.5), width: 1),
                ),
                child: Text(
                  '$percentage de Ganancia', 
                  style: GoogleFonts.inter(color: tagColor, fontSize: 13, fontWeight: FontWeight.bold)
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$$price', style: GoogleFonts.outfit(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
                child: Text('/ $period', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.people_alt_outlined, color: isFull ? Colors.redAccent : AppTheme.primary, size: 16),
              const SizedBox(width: 6),
              Text(
                isFull ? 'Cupos Agotados' : 'Cupos: $availableSlots/100',
                style: GoogleFonts.inter(
                  color: isFull ? Colors.redAccent : AppTheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.star, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('¡Primer mes al 90% de descuento!', style: GoogleFonts.inter(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Empieza hoy por solo \$${(price * 0.1).toStringAsFixed(2)}. Renueva a precio regular el próximo mes.', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (features.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...features.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, color: tagColor, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      feature,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14, height: 1.3),
                    ),
                  ),
                ],
              ),
            )),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: isFull ? null : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupSetupScreen(
                      planName: name,
                      price: price,
                      isGroup: isGroup,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isFull ? Colors.white12 : (isPremium ? const Color(0xFFFFD700) : AppTheme.primary),
                foregroundColor: isFull ? Colors.white38 : (isPremium ? Colors.black : Colors.white),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: isFull ? 0 : (isPremium ? 8 : 2),
                shadowColor: isPremium ? const Color(0xFFFFD700).withValues(alpha: 0.5) : AppTheme.primary.withValues(alpha: 0.5),
              ),
              child: Text(
                isFull ? 'Agotado' : 'Seleccionar Plan', 
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)
              ),
            ),
          )
        ],
      ),
    );
  }
}
