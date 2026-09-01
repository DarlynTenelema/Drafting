import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'entrepreneur_dashboard_screen.dart';
import 'calculator_screen.dart';
import 'legal_screen.dart';
import 'group_setup_screen.dart';
import 'leaderboard_screen.dart';
import '../core/services/entrepreneur_service.dart';

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
      body: FutureBuilder<List<dynamic>>(
        future: EntrepreneurService().getCreatorPlans(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Error cargando los planes', style: TextStyle(color: Colors.white)));
          }

          final plans = snapshot.data!;
          final otpPlans = plans.where((p) => p['isGroup'] == false).toList();
          final groupPlans = plans.where((p) => p['isGroup'] == true).toList();

          return ListView(
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
              ...otpPlans.map((plan) => _buildPlanCard(plan)).toList(),
              
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
              ...groupPlans.map((plan) => _buildPlanCard(plan)).toList(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlanCard(dynamic plan) {
    String name = plan['name'];
    String percentage = plan['percentage'];
    double price = (plan['price'] as num).toDouble();
    String period = plan['period'];
    bool isGroup = plan['isGroup'] ?? false;
    int availableSlots = plan['availableSlots'] ?? 0;
    int totalSlots = plan['totalSlots'] ?? 100;
    List<String> features = (plan['features'] as List<dynamic>).map((e) => e.toString()).toList();

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
                isFull ? 'Cupos Agotados' : 'Cupos: $availableSlots/$totalSlots',
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
                      Text('¡Primer mes totalmente GRATIS!', style: GoogleFonts.inter(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Empieza hoy sin costo. Renueva a precio regular el próximo mes.', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, height: 1.3)),
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
