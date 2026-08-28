import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../core/services/finance_service.dart';
import '../core/services/entrepreneur_service.dart';
import 'withdraw_screen.dart';
import 'finance_dashboard_screen.dart';

class EntrepreneurDashboardScreen extends StatefulWidget {
  const EntrepreneurDashboardScreen({super.key});

  @override
  State<EntrepreneurDashboardScreen> createState() => _EntrepreneurDashboardScreenState();
}

class _EntrepreneurDashboardScreenState extends State<EntrepreneurDashboardScreen> {
  final TextEditingController _aiRulesController = TextEditingController();
  
  // AI Model Controllers
  final TextEditingController _earlyGameCtrl = TextEditingController();
  final TextEditingController _lateGameCtrl = TextEditingController();
  final TextEditingController _combosCtrl = TextEditingController();
  final TextEditingController _synergiesCtrl = TextEditingController();
  final TextEditingController _countersCtrl = TextEditingController();
  final TextEditingController _coreBuildCtrl = TextEditingController();
  final TextEditingController _runesCtrl = TextEditingController();
  final TextEditingController _situationalCtrl = TextEditingController();

  String? _selectedChampion;
  List<String> _champions = [];
  bool _isLoadingChampions = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FinanceService().fetchDashboardStats();
      _loadChampions();
    });
  }

  Future<void> _loadChampions() async {
    final list = await EntrepreneurService().getMyChampions();
    if (mounted) {
      setState(() {
        if (list.isEmpty) {
          _champions = ['Ahri']; // Fallback
        } else {
          _champions = list;
        }
        _selectedChampion = _champions.first;
        _isLoadingChampions = false;
      });
    }
  }

  @override
  void dispose() {
    _aiRulesController.dispose();
    _earlyGameCtrl.dispose();
    _lateGameCtrl.dispose();
    _combosCtrl.dispose();
    _synergiesCtrl.dispose();
    _countersCtrl.dispose();
    _coreBuildCtrl.dispose();
    _runesCtrl.dispose();
    _situationalCtrl.dispose();
    super.dispose();
  }

  Future<void> _connectStripe() async {
    final url = await FinanceService().getStripeOnboardingLink();
    if (url != null) {
      if (!await launchUrl(Uri.parse(url))) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace.')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al conectar con Stripe.')));
    }
  }

  Future<void> _saveAIModel() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Guardando y validando con Gemini...')),
    );

    final result = await EntrepreneurService().saveAIModel({
      'champion_name': _selectedChampion ?? 'Ahri',
      'early_game_strategy': _earlyGameCtrl.text,
      'late_game_strategy': _lateGameCtrl.text,
      'combos': _combosCtrl.text,
      'synergies': _synergiesCtrl.text,
      'counters': _countersCtrl.text,
      'core_build': _coreBuildCtrl.text,
      'spells_and_runes': _runesCtrl.text,
      'situational_items': _situationalCtrl.text,
    });

    if (mounted) {
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Modelo IA guardado y entrenado exitosamente!')),
        );
      } else {
        _showStrikeWarning(result['message'], result['banned'] ?? false);
      }
    }
  }

  void _showStrikeWarning(String message, bool isBanned) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: isBanned ? Colors.red : Colors.orange),
            const SizedBox(width: 8),
            Text(
              isBanned ? 'Cuenta Suspendida' : 'Advertencia de Infracción',
              style: GoogleFonts.outfit(color: isBanned ? Colors.red : Colors.orange, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (isBanned) {
                // Logout user and redirect to login
                Navigator.of(context).pushReplacementNamed('/login'); // Assuming a /login route exists
              }
            },
            child: const Text('Entendido', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            'Panel de Creador',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textMuted,
            tabs: [
              Tab(icon: Icon(Icons.account_balance_wallet), text: 'Finanzas'),
              Tab(icon: Icon(Icons.psychology), text: 'Motor IA'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFinanceTab(),
            _buildAITab(),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Revenue Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, Color(0xFF9D4EDD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Balance Disponible',
                      style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                    ),
                    const Icon(Icons.account_balance, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: FinanceService(),
                    builder: (context, child) {
                      return Text(
                        '\$${FinanceService().totalUsd.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WithdrawScreen(financeService: FinanceService()),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Retirar Fondos', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FinanceDashboardScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('Ver Historial de Ingresos'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Stripe Connect
          Text(
            'Conexión Bancaria',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF635BFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.credit_card, color: Color(0xFF635BFF)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stripe Connect', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('Recibe pagos seguros', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _connectStripe,
                  child: Text('Conectar', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAITab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuración del Campeón',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'La Inteligencia artificial usará estas reglas secretas para asesorar a tus suscriptores en tiempo real.',
            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 24),
          
          const SizedBox(height: 24),
          
          // Champion Dropdown & Add Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Campeón Principal', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _showAddChampionDialog,
                icon: const Icon(Icons.add, size: 16, color: AppTheme.primary),
                label: Text('Añadir Campeón', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
              )
            ],
          ),
          const SizedBox(height: 8),
          _isLoadingChampions
              ? const Center(child: CircularProgressIndicator())
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedChampion,
                      dropdownColor: AppTheme.surface,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                      isExpanded: true,
                      items: _champions.map((String champion) {
                        return DropdownMenuItem(
                          value: champion,
                          child: Text(champion, style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedChampion = newValue!;
                          // Here we could load existing data for the selected champion if we had it cached
                          _clearForm();
                        });
                      },
                    ),
                  ),
                ),
          
          const SizedBox(height: 24),
          
          _buildTextField('Estrategia de Early Game (Min 0-10)', _earlyGameCtrl),
          _buildTextField('Estrategia de Late Game', _lateGameCtrl),
          _buildTextField('Combos Principales', _combosCtrl),
          _buildTextField('Mejores Aliados (Sinergias)', _synergiesCtrl),
          _buildTextField('Counters (Peores enfrentamientos)', _countersCtrl),
          _buildTextField('Build Principal (Objetos Core)', _coreBuildCtrl),
          _buildTextField('Hechizos y Runas Principales', _runesCtrl),
          _buildTextField('Objetos Situacionales', _situationalCtrl),
          
          const SizedBox(height: 32),
          
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _saveAIModel,
              icon: const Icon(Icons.save),
              label: const Text('Actualizar y Entrenar IA'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
            ),
          ),
        ],
      ),
    );
  }

  void _clearForm() {
    _earlyGameCtrl.clear();
    _lateGameCtrl.clear();
    _combosCtrl.clear();
    _synergiesCtrl.clear();
    _countersCtrl.clear();
    _coreBuildCtrl.clear();
    _runesCtrl.clear();
    _situationalCtrl.clear();
  }

  void _showAddChampionDialog() {
    String newChampion = '';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Añadir Nuevo Campeón', style: GoogleFonts.outfit(color: Colors.white)),
          content: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Nombre del campeón (Ej. Yasuo)',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: AppTheme.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (val) => newChampion = val,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                if (newChampion.isNotEmpty) {
                  setState(() {
                    if (!_champions.contains(newChampion)) {
                      _champions.add(newChampion);
                    }
                    _selectedChampion = newChampion;
                    _clearForm();
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Añadir', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }
    );
  }
}
