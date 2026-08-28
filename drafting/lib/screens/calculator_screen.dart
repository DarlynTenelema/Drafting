import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

class EntrepreneurPlan {
  final String name;
  final double price;
  final double percentage; // Ej: 0.50 = 50%
  
  EntrepreneurPlan(this.name, this.price, this.percentage);
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final List<EntrepreneurPlan> _availablePlans = [
    EntrepreneurPlan('OTP - \$10/mes (50%)', 10, 0.50),
    EntrepreneurPlan('OTP - \$20/mes (60%)', 20, 0.60),
    EntrepreneurPlan('OTP - \$30/mes (70%)', 30, 0.70),
    EntrepreneurPlan('OTP - \$40/mes (80%)', 40, 0.80),
    EntrepreneurPlan('OTP - \$50/mes (90%)', 50, 0.90),
    EntrepreneurPlan('Grupo - \$100/mes (50%)', 100, 0.50),
    EntrepreneurPlan('Grupo - \$200/mes (60%)', 200, 0.60),
    EntrepreneurPlan('Grupo - \$300/mes (70%)', 300, 0.70),
    EntrepreneurPlan('Grupo - \$400/mes (80%)', 400, 0.80),
    EntrepreneurPlan('Grupo - \$500/mes (90%)', 500, 0.90),
  ];

  final List<double> _consumerPrices = [0.24, 0.49, 0.99, 1.58, 2.99, 5.99, 9.99, 19.99, 59.99, 99.99, 199.99];

  late EntrepreneurPlan _selectedPlan;
  double _selectedConsumerPrice = 9.99;
  double _subscribers = 100;
  int _groupMembers = 1;
  
  final double _googlePlayFee = 0.15; // 15%
  
  // Costo estimado IA dinámico basado en el precio
  double get _geminiCostPerSub => _selectedConsumerPrice * 0.10;

  @override
  void initState() {
    super.initState();
    _selectedPlan = _availablePlans[0];
  }

  // Cálculos
  double get _grossRevenue => _subscribers * _selectedConsumerPrice;
  double get _googlePlayDeduction => _grossRevenue * _googlePlayFee;
  double get _netPostGoogle => _grossRevenue - _googlePlayDeduction;
  double get _entrepreneurShare => _netPostGoogle * _selectedPlan.percentage;
  double get _apiCosts => _subscribers * _geminiCostPerSub;
  double get _withdrawalFee => _subscribers > 0 ? 2.0 : 0.0; // Tarifa plana por retiro
  double get _finalProfit => _entrepreneurShare - _apiCosts - _withdrawalFee;
  
  bool get _isGroupPlan => _selectedPlan.name.contains('Grupo');
  double get _profitPerMember => _isGroupPlan && _groupMembers > 0 ? _finalProfit / _groupMembers : _finalProfit;
  
  double get _maxSubscribers => _selectedPlan.price * 10;
  double get _profitPerSub => (_selectedConsumerPrice * (1 - _googlePlayFee) * _selectedPlan.percentage) - _geminiCostPerSub;
  int get _breakEvenSubs => _profitPerSub > 0 ? (_selectedPlan.price / _profitPerSub).ceil() : 0;

  String _getDurationText(double price) {
    if (price == 0.24 || price == 0.49 || price == 0.99) return 'Diario';
    if (price == 1.58 || price == 2.99) return 'Semanal';
    if (price == 5.99) return 'Semanal (U) / Mensual (P)';
    if (price == 9.99 || price == 19.99) return 'Mensual';
    if (price == 59.99 || price == 99.99 || price == 199.99) return 'Anual';
    return 'mes';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: Text(
          'Calculadora de Ganancias',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan Dropdown
            Text('Plan que deseas adquirir (Drafting)', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<EntrepreneurPlan>(
                  value: _selectedPlan,
                  dropdownColor: AppTheme.surface,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  isExpanded: true,
                  items: _availablePlans.map((plan) {
                    return DropdownMenuItem(
                      value: plan,
                      child: Text(plan.name, style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() { 
                      _selectedPlan = val!; 
                      if (_subscribers > _maxSubscribers) {
                        _subscribers = _maxSubscribers;
                      }
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Consumer Price Dropdown
            Text('Precio al que venderás tu IA', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<double>(
                  value: _selectedConsumerPrice,
                  dropdownColor: AppTheme.surface,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  isExpanded: true,
                  items: _consumerPrices.map((price) {
                    return DropdownMenuItem(
                      value: price,
                      child: Text('\$$price / ${_getDurationText(price)}', style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() { _selectedConsumerPrice = val!; });
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_isGroupPlan) ...[
              Text('Número de integrantes del grupo', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Ej. 5',
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _groupMembers = int.tryParse(val) ?? 1;
                      if (_groupMembers < 1) _groupMembers = 1;
                    });
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Subscribers Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Suscriptores Estimados', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                Text('${_subscribers.toInt()} / ${_maxSubscribers.toInt()}', style: GoogleFonts.outfit(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            Slider(
              value: _subscribers > _maxSubscribers ? _maxSubscribers : _subscribers,
              min: 0,
              max: _maxSubscribers,
              divisions: 100,
              activeColor: AppTheme.primary,
              inactiveColor: Colors.white.withValues(alpha: 0.1),
              onChanged: (val) {
                setState(() { _subscribers = val; });
              },
            ),

            const SizedBox(height: 32),
            const Divider(color: Colors.white24),
            const SizedBox(height: 24),

            // Results Card
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.15),
                    AppTheme.surface,
                  ],
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    blurRadius: 24,
                    spreadRadius: 8,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics_outlined, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Text('Desglose Mensual', style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  _buildRow('Ingreso Bruto', _grossRevenue),
                  _buildRow('Google Play (15%)', -_googlePlayDeduction, isDeduction: true),
                  _buildRow('Disponible a repartir', _netPostGoogle, isSubtotal: true),
                  
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Divider(color: Colors.white12)),
                  
                  _buildRow('Tu Porcentaje (${(_selectedPlan.percentage * 100).toInt()}%)', _entrepreneurShare),
                  _buildRow('Costo API Gemini', -_apiCosts, isDeduction: true),
                  _buildRow('Comisión Retiro (Stripe)', -_withdrawalFee, isDeduction: true),
                  
                  const Padding(padding: EdgeInsets.symmetric(vertical: 20.0), child: Divider(color: Colors.white24)),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Ganancia\nNeta Limpia', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, height: 1.2)),
                      Text('\$${_finalProfit.toStringAsFixed(2)}', style: GoogleFonts.outfit(color: const Color(0xFF00E5FF), fontSize: 36, fontWeight: FontWeight.w900)),
                    ],
                  ),

                  if (_isGroupPlan) ...[
                    const Padding(padding: EdgeInsets.symmetric(vertical: 16.0), child: Divider(color: Colors.white24)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Ganancia\nPor Integrante', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold, height: 1.2)),
                        Text('\$${_profitPerMember.toStringAsFixed(2)}', style: GoogleFonts.outfit(color: const Color(0xFF00E5FF), fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Meta Sugerida
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lightbulb_outline, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text('Meta Sugerida', style: GoogleFonts.inter(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _profitPerSub > 0 
                    ? 'Para recuperar el costo mensual de tu plan (\$${_selectedPlan.price}) necesitas al menos $_breakEvenSubs usuarios.\n\nPara maximizar tu rentabilidad y que el negocio sea verdaderamente estable, te sugerimos acercarte a tu límite de ventas de ${_maxSubscribers.toInt()} usuarios.'
                    : 'Con este precio, el porcentaje y el costo de API superan el margen de ganancia. Te sugerimos seleccionar un precio mayor.',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            Text(
              '* Importante: Estas son proyecciones. El costo de la API es dinámico. La comisión de Stripe no está incluida.',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, double amount, {bool isDeduction = false, bool isSubtotal = false}) {
    Color textColor = Colors.white;
    if (isDeduction) textColor = Colors.red[300]!;
    if (isSubtotal) textColor = AppTheme.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(color: isSubtotal ? AppTheme.textMuted : Colors.white, fontSize: 14)),
          Text(
            '${isDeduction ? '' : amount >= 0 ? '' : '-'}\$${amount.abs().toStringAsFixed(2)}',
            style: GoogleFonts.inter(color: textColor, fontWeight: isSubtotal ? FontWeight.normal : FontWeight.w600, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
