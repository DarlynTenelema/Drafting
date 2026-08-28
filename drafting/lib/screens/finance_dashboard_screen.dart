import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

import '../core/services/finance_service.dart';
import '../theme/app_theme.dart';
import 'withdraw_screen.dart';

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  final FinanceService _financeService = FinanceService();

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    await _financeService.fetchDashboardStats();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Panel Financiero', style: GoogleFonts.outfit(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _financeService.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBalanceCard(context),
                    const SizedBox(height: 32),
                    Text(
                      'Impacto y Crecimiento',
                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    _buildChart(),
                    const SizedBox(height: 32),
                    Text(
                      'Últimas Donaciones',
                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    _buildRecentTransactions(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBalanceCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Acumulado',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '\$${_financeService.totalUsd.toStringAsFixed(2)}',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => WithdrawScreen(financeService: _financeService)),
                );
                if (result == true) {
                  _loadStats();
                }
              },
              child: Text(
                'Retirar Fondos',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildChart() {
    if (_financeService.transactions.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text('No hay datos suficientes', style: GoogleFonts.inter(color: AppTheme.textMuted)),
        ),
      );
    }

    // Agrupar transacciones reales por día
    Map<int, double> dailyEarnings = {};
    double maxUsd = 0;

    for (var t in _financeService.transactions) {
      final amount = (t['AmountUSD'] as num).toDouble();
      if (amount <= 0) continue; // solo donaciones / ingresos

      // Parse date
      final dateStr = t['CreatedAt'];
      if (dateStr != null) {
        final date = DateTime.tryParse(dateStr);
        if (date != null) {
          final day = date.day;
          dailyEarnings[day] = (dailyEarnings[day] ?? 0) + amount;
        }
      }
    }

    List<FlSpot> spots = [];
    if (dailyEarnings.isEmpty) {
       // fallback if no valid dates found
       for (int i = 0; i < _financeService.transactions.length; i++) {
         double amount = (_financeService.transactions[i]['AmountUSD'] as num).toDouble();
         if (amount > maxUsd) maxUsd = amount;
         spots.add(FlSpot(i.toDouble(), amount));
       }
    } else {
      final sortedDays = dailyEarnings.keys.toList()..sort();
      int xIndex = 0;
      for (var day in sortedDays) {
        final amount = dailyEarnings[day]!;
        if (amount > maxUsd) maxUsd = amount;
        spots.add(FlSpot(xIndex.toDouble(), amount));
        xIndex++;
      }
    }

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: spots.length > 1 ? (spots.length - 1).toDouble() : 1,
          minY: 0,
          maxY: maxUsd * 1.5,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppTheme.primary,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.primary.withValues(alpha: 0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTransactions() {
    if (_financeService.transactions.isEmpty) {
      return Center(
        child: Text('No has recibido donaciones aún.', style: GoogleFonts.inter(color: AppTheme.textMuted)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _financeService.transactions.length,
      itemBuilder: (context, index) {
        final t = _financeService.transactions[index];
        final amount = (t['AmountUSD'] as num).toDouble();
        final amountCoin = (t['AmountCoin'] as num).toDouble();
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.diamond, color: Colors.blueAccent),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Esencia Azul', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                      Text('+${amountCoin.toInt()} esencias', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              Text('+\$${amount.toStringAsFixed(2)}', style: GoogleFonts.outfit(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        );
      },
    );
  }
}
