import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'entrepreneur_dashboard_screen.dart';
import 'calculator_screen.dart';
import 'legal_screen.dart';
import 'group_setup_screen.dart';
import 'leaderboard_screen.dart';
import 'invitations_screen.dart';
import '../core/services/entrepreneur_service.dart';
import 'group_member_dashboard_screen.dart';

class EntrepreneurOnboardingScreen extends StatefulWidget {
  const EntrepreneurOnboardingScreen({super.key});

  @override
  State<EntrepreneurOnboardingScreen> createState() => _EntrepreneurOnboardingScreenState();
}

class _EntrepreneurOnboardingScreenState extends State<EntrepreneurOnboardingScreen> {
  bool _showDashboard = false;
  Map<String, dynamic>? _draftGroup;

  @override
  void initState() {
    super.initState();
    _checkDashboardVisibility();
  }

  void _checkDashboardVisibility() async {
    final isEligible = await EntrepreneurService().checkFirstTimeEligibility();
    final draft = await EntrepreneurService().fetchMyDraftGroup();
    if (mounted) {
      if (draft == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('fetchMyDraftGroup returned null!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Found draft: ${draft['id'] ?? draft['ID']}')));
      }
      setState(() {
        _showDashboard = !isEligible;
        _draftGroup = draft;
      });
    }
  }

  String _getPlanNameForId(String? planId) {
    if (planId == null) return 'Borrador';
    if (planId == '10' || planId == '10.0' || planId == '10.00') return 'Plan Emprendedor Individual';
    if (planId == '20' || planId == '20.0' || planId == '20.00') return 'Plan Emprendedor Individual (Anual)';
    if (planId == '300' || planId == '300.0' || planId == '300.00') return 'Plan Empresarial (300)';
    if (planId == '500' || planId == '500.0' || planId == '500.00') return 'Plan Corporativo (500)';
    return 'Borrador';
  }

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
          if (_showDashboard) ...[
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
          ],
          FloatingActionButton(
            heroTag: 'my_group',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GroupMemberDashboardScreen()));
            },
            backgroundColor: Colors.purple,
            child: const Icon(Icons.group, color: Colors.white),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'invitations',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InvitationsScreen()));
            },
            backgroundColor: Colors.orange,
            child: const Icon(Icons.mail, color: Colors.white),
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
      bottomNavigationBar: _draftGroup != null ? SafeArea(
        child: GestureDetector(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupSetupScreen(
                planId: _draftGroup!['subscription_plan']?.toString() ?? _draftGroup!['SubscriptionPlan']?.toString(),
                planName: _getPlanNameForId(_draftGroup!['subscription_plan']?.toString() ?? _draftGroup!['SubscriptionPlan']?.toString()),
                price: 0.0,
                isGroup: (_draftGroup!['subscription_plan'] ?? _draftGroup!['SubscriptionPlan']) != '10' && (_draftGroup!['subscription_plan'] ?? _draftGroup!['SubscriptionPlan']) != '20',
                draftGroup: _draftGroup,
              ),
            )).then((_) => _checkDashboardVisibility());
          },
          child: Container(
            margin: const EdgeInsets.only(left: 20, right: 85, bottom: 20, top: 5), // Leaves space on the right for the floating buttons
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.deepOrange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_document, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reanudar Borrador',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        (_draftGroup!['product_name']?.toString().isNotEmpty == true 
                            ? _draftGroup!['product_name']?.toString() 
                            : (_draftGroup!['ProductName']?.toString().isNotEmpty == true 
                                ? _draftGroup!['ProductName']?.toString() 
                                : (_draftGroup!['name']?.toString() ?? _draftGroup!['Name']?.toString() ?? 'Sin nombre'))) ?? 'Sin nombre',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
              ],
            ),
          ),
        ),
      ) : null,
      body: FutureBuilder<List<dynamic>>(
        future: EntrepreneurService().getCreatorPlans(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Error cargando los planes', style: TextStyle(color: Colors.white)));
          }

          final plans = snapshot.data ?? [];
          final otpPlans = plans.where((p) => p['isGroup'] == false).toList();
          final groupPlans = plans.where((p) => p['isGroup'] == true).toList();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
    String name = plan['name']?.toString() ?? plan['Name']?.toString() ?? 'Plan';
    String percentage = plan['percentage']?.toString() ?? plan['Percentage']?.toString() ?? '0%';
    double price = ((plan['price'] ?? plan['Price']) as num?)?.toDouble() ?? 0.0;
    String period = plan['period']?.toString() ?? plan['Period']?.toString() ?? 'mes';
    bool isGroup = plan['isGroup'] ?? plan['IsGroup'] ?? false;
    int availableSlots = plan['availableSlots'] ?? plan['AvailableSlots'] ?? 0;
    int totalSlots = plan['totalSlots'] ?? plan['TotalSlots'] ?? 100;
    List<String> features = ((plan['features'] ?? plan['Features']) as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

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
                      planId: plan['planId']?.toString() ?? plan['PlanID']?.toString(),
                    ),
                  ),
                ).then((_) => _checkDashboardVisibility());
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
