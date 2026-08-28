import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../core/services/finance_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final FinanceService _financeService = FinanceService();
  List<dynamic> _topCreators = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    final data = await _financeService.getLeaderboard();
    if (mounted) {
      setState(() {
        _topCreators = data;
        _isLoading = false;
      });
    }
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
          'Top Creadores (Mensual)',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : _topCreators.isEmpty
            ? const Center(child: Text('No hay datos disponibles', style: TextStyle(color: Colors.white)))
            : ListView.builder(
                padding: const EdgeInsets.all(24.0),
                itemCount: _topCreators.length,
                itemBuilder: (context, index) {
                  final creator = _topCreators[index];
                  final bool isPremium = creator['isPremium'] ?? false;
                  final bool isPro = creator['isPro'] ?? false;

          Color badgeColor = Colors.white24;
          if (index == 0) {
            badgeColor = const Color(0xFFFFD700); // Gold
          } else if (index == 1) badgeColor = const Color(0xFFC0C0C0); // Silver
          else if (index == 2) badgeColor = const Color(0xFFCD7F32); // Bronze

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: index < 3 ? badgeColor.withValues(alpha: 0.5) : Colors.white12,
                width: index < 3 ? 1.5 : 1.0,
              ),
              boxShadow: index < 3
                  ? [
                      BoxShadow(
                        color: badgeColor.withValues(alpha: 0.1),
                        blurRadius: 12,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
            child: Row(
              children: [
                // Rank Number
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < 3 ? badgeColor.withValues(alpha: 0.2) : Colors.transparent,
                    border: Border.all(
                      color: index < 3 ? badgeColor : Colors.white24,
                    ),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: GoogleFonts.outfit(
                      color: index < 3 ? badgeColor : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Creator Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            creator['name'],
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isPremium || isPro)
                            Icon(
                              Icons.verified,
                              color: isPremium ? const Color(0xFFFFD700) : const Color(0xFF00E5FF),
                              size: 16,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        creator['champion'] ?? 'Creador',
                        style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                
                // Earnings
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${(creator['earnings'] as num).toDouble().toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF00E5FF),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'este mes',
                      style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
