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
  
  List<Map<String, dynamic>> _savedModels = [];
  bool _isLoadingModels = true;

  // Settings
  final TextEditingController _groupNameCtrl = TextEditingController();
  bool _isProductHidden = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FinanceService().fetchDashboardStats();
      _loadChampions();
      _loadSavedModels();
    });
  }

  Future<void> _loadSavedModels() async {
    final models = await EntrepreneurService().getAllAIModels();
    if (mounted) {
      setState(() {
        _savedModels = models;
        _isLoadingModels = false;
      });
    }
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
    _groupNameCtrl.dispose();
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
      length: 4,
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
              Tab(icon: Icon(Icons.storage), text: 'Base de datos'),
              Tab(icon: Icon(Icons.settings), text: 'Ajustes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFinanceTab(),
            _buildAITab(),
            _buildDatabaseTab(),
            _buildSettingsTab(),
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

  Widget _buildDatabaseTab() {
    if (_isLoadingModels) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_savedModels.isEmpty) {
      return Center(
        child: Text(
          'No hay modelos IA guardados aún.',
          style: GoogleFonts.inter(color: AppTheme.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24.0),
      itemCount: _savedModels.length,
      itemBuilder: (context, index) {
        final model = _savedModels[index];
        final championName = model['champion_name'] ?? 'Desconocido';
        final date = model['created_at'] ?? 'Reciente';

        return Card(
          color: AppTheme.surface,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              iconColor: AppTheme.primary,
              collapsedIconColor: Colors.white70,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    championName,
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    date.toString().split(' ').first,
                    style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildEditableField('Estrategia de Early Game', model['early_game_strategy'] ?? '', (val) => model['early_game_strategy'] = val),
                      _buildEditableField('Estrategia de Late Game', model['late_game_strategy'] ?? '', (val) => model['late_game_strategy'] = val),
                      _buildEditableField('Combos Principales', model['combos'] ?? '', (val) => model['combos'] = val),
                      _buildEditableField('Mejores Aliados (Sinergias)', model['synergies'] ?? '', (val) => model['synergies'] = val),
                      _buildEditableField('Counters (Peores enfrentamientos)', model['counters'] ?? '', (val) => model['counters'] = val),
                      _buildEditableField('Build Principal (Objetos Core)', model['core_build'] ?? '', (val) => model['core_build'] = val),
                      _buildEditableField('Hechizos y Runas Principales', model['spells_and_runes'] ?? '', (val) => model['spells_and_runes'] = val),
                      _buildEditableField('Objetos Situacionales', model['situational_items'] ?? '', (val) => model['situational_items'] = val),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => _confirmDeleteModel(championName),
                            tooltip: 'Eliminar',
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: () => _updateExistingModel(model),
                            icon: const Icon(Icons.save),
                            label: const Text('Guardar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableField(String label, String initialValue, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: initialValue,
            onChanged: onChanged,
            maxLines: null,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateExistingModel(Map<String, dynamic> model) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardando cambios...')));
    final res = await EntrepreneurService().updateAIModel(model);
    if (mounted) {
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modelo actualizado correctamente.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? 'Error al actualizar')));
      }
    }
  }

  void _confirmDeleteModel(String championName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('¿Eliminar $championName?', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text('Se eliminarán todos los datos guardados de este campeón de tu base de datos. Esta acción no se puede deshacer.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoadingModels = true);
              final res = await EntrepreneurService().deleteAIModel(championName);
              if (mounted) {
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modelo eliminado.')));
                  _loadSavedModels();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? 'Error al eliminar')));
                  setState(() => _isLoadingModels = false);
                }
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ajustes del Grupo',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Text('Nombre del Grupo', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _groupNameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.surface,
              hintText: 'Ej. Maestros de Ahri',
              hintStyle: const TextStyle(color: Colors.white30),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _showConfirmationModal(
              title: '¿Cambiar imagen?',
              content: '¿Estás seguro de que deseas cambiar la imagen del producto?',
              onConfirm: () async {
                // Future image picker logic
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selección de imagen...')));
              }
            ),
            icon: const Icon(Icons.image),
            label: const Text('Cambiar Imagen del Producto'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surface,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _showConfirmationModal(
                title: '¿Guardar Cambios?',
                content: '¿Estás seguro de que deseas guardar estos ajustes?',
                onConfirm: () async {
                  final res = await EntrepreneurService().updateGroupSettings(_groupNameCtrl.text, null);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['success'] == true ? 'Ajustes guardados.' : 'Error: ${res['error']}')));
                  }
                }
              ),
              icon: const Icon(Icons.save),
              label: const Text('Guardar Ajustes de Grupo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          
          const SizedBox(height: 48),
          const Divider(color: Colors.white24),
          const SizedBox(height: 24),
          
          Text(
            'Visibilidad de la Tienda',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Si ocultas tu producto, ya no aparecerá en la tienda para nuevos compradores. Los suscriptores actuales podrán seguir usándolo hasta que su plan termine.',
            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isProductHidden ? 'Producto Oculto' : 'Producto Visible',
                  style: GoogleFonts.inter(color: _isProductHidden ? Colors.orange : Colors.green, fontWeight: FontWeight.bold),
                ),
                Switch(
                  value: _isProductHidden,
                  activeColor: Colors.orange,
                  onChanged: (val) {
                    _showConfirmationModal(
                      title: val ? '¿Ocultar Producto?' : '¿Hacer Visible el Producto?',
                      content: val 
                        ? 'Al ocultar este producto, nadie más podrá comprarlo.' 
                        : 'El producto volverá a estar disponible en la tienda.',
                      onConfirm: () async {
                        final res = await EntrepreneurService().toggleProductVisibility(val);
                        if (mounted) {
                          if (res['success'] == true) {
                            setState(() => _isProductHidden = val);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${res['error']}')));
                          }
                        }
                      }
                    );
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 48),
          const Divider(color: Colors.white24),
          const SizedBox(height: 24),

          Text(
            'Zona de Peligro',
            style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Una vez que elimines tu producto, no hay vuelta atrás. Por favor, asegúrate antes de hacerlo.',
            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isDeleting ? null : _handleDeleteProduct,
              icon: _isDeleting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.delete_forever),
              label: Text(_isDeleting ? 'Procesando...' : 'Eliminar Producto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteProduct() async {
    setState(() => _isDeleting = true);

    final checkRes = await EntrepreneurService().checkActiveSubscriptions();
    
    if (!mounted) return;
    setState(() => _isDeleting = false);

    bool hasActive = checkRes['hasActive'] ?? false;
    String? lastEndDateStr = checkRes['lastEndDate'];

    if (hasActive && lastEndDateStr != null) {
      DateTime lastEndDate = DateTime.parse(lastEndDateStr);
      String formattedDate = "${lastEndDate.day}/${lastEndDate.month}/${lastEndDate.year}";
      
      _showConfirmationModal(
        title: 'Tienes compras activas',
        content: 'No es posible eliminar este producto hoy.\n\n¿Deseas habilitar la eliminación automática cuando el último plan vendido termine? El último plan termina el $formattedDate. El producto se eliminará un día después de esta fecha.',
        confirmText: 'Activar eliminación automática',
        onConfirm: () async {
          setState(() => _isDeleting = true);
          final res = await EntrepreneurService().scheduleProductDeletion(lastEndDate.add(const Duration(days: 1)));
          if (mounted) {
            setState(() => _isDeleting = false);
            if (res['success'] == true) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eliminación diferida programada.')));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${res['error']}')));
            }
          }
        },
      );
    } else {
      _showConfirmationModal(
        title: '¿Eliminar producto definitivamente?',
        content: 'No tienes suscripciones activas. El producto se eliminará inmediatamente y de forma permanente. ¿Estás seguro?',
        confirmText: 'Eliminar inmediatamente',
        onConfirm: () async {
          setState(() => _isDeleting = true);
          final res = await EntrepreneurService().deleteProductNow();
          if (mounted) {
            setState(() => _isDeleting = false);
            if (res['success'] == true) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto eliminado exitosamente.')));
              // Redirect to previous screen or dashboard
              Navigator.of(context).pop();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${res['error']}')));
            }
          }
        },
      );
    }
  }

  void _showConfirmationModal({required String title, required String content, required VoidCallback onConfirm, String confirmText = 'Aceptar'}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title, style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(content, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: Text(confirmText, style: const TextStyle(color: Colors.white)),
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
