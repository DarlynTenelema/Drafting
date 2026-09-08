import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/services/entrepreneur_service.dart';
import '../theme/app_theme.dart';

class MemberUploadKnowledgeScreen extends StatefulWidget {
  const MemberUploadKnowledgeScreen({super.key});

  @override
  State<MemberUploadKnowledgeScreen> createState() => _MemberUploadKnowledgeScreenState();
}

class _MemberUploadKnowledgeScreenState extends State<MemberUploadKnowledgeScreen> {
  final _championCtrl = TextEditingController();
  final _earlyGameCtrl = TextEditingController();
  final _lateGameCtrl = TextEditingController();
  final _synergiesCtrl = TextEditingController();
  final _countersCtrl = TextEditingController();
  final _buildCtrl = TextEditingController();
  final _runesCtrl = TextEditingController();
  final _situationalCtrl = TextEditingController();

  bool _isSaving = false;

  void _saveData() async {
    if (_championCtrl.text.isEmpty || _earlyGameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Al menos ingresa el nombre del campeón y la estrategia de early game.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Analizando y subiendo conocimiento...')),
    );

    final championData = {
      'champion_name': _championCtrl.text.trim(),
      'early_game_strategy': _earlyGameCtrl.text.trim(),
      'late_game_strategy': _lateGameCtrl.text.trim(),
      'synergies': _synergiesCtrl.text.trim(),
      'counters': _countersCtrl.text.trim(),
      'core_build': _buildCtrl.text.trim(),
      'spells_and_runes': _runesCtrl.text.trim(),
      'situational_items': _situationalCtrl.text.trim(),
    };

    final result = await EntrepreneurService().saveAIModel(championData);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('¡Conocimiento de ${_championCtrl.text} subido a la base de datos de tu grupo!')),
      );
      Navigator.pop(context);
    } else {
      bool isBanned = result['banned'] == true;
      String message = result['message']?.toString() ?? result['error']?.toString() ?? 'Error desconocido';
      if (isBanned || message.toLowerCase().contains('strike') || message.toLowerCase().contains('infracción')) {
        _showStrikeWarning(message, isBanned);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
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
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (isBanned) {
                // Logout or handle ban
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Aportar al Grupo', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sube conocimiento detallado sobre un campeón para entrenar la Inteligencia Artificial de tu grupo.',
              style: GoogleFonts.inter(color: AppTheme.textLight, fontSize: 14),
            ),
            const SizedBox(height: 24),
            
            _buildTextField('Nombre del Campeón (Obligatorio)', _championCtrl, 'Ej. Ahri, Yasuo...'),
            _buildTextField('Early Game (Min 0-10) (Obligatorio)', _earlyGameCtrl, 'Ej. Jugar pasivo hasta nivel 5...'),
            _buildTextField('Late Game', _lateGameCtrl, 'Ej. Buscar flancos...'),
            _buildTextField('Sinergias', _synergiesCtrl, 'Ej. Malphite, Amumu...'),
            _buildTextField('Counters', _countersCtrl, 'Ej. Zed, Fizz...'),
            _buildTextField('Runas', _runesCtrl, 'Ej. Flash, Ignición...'),
            _buildTextField('Build Principal', _buildCtrl, 'Ej. Luden, Sombrero...'),
            _buildTextField('Objetos Situacionales', _situationalCtrl, 'Ej. Cortacuras, Zhonya...'),
            
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveData,
                icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.cloud_upload),
                label: Text(_isSaving ? 'Subiendo...' : 'Subir a la BD del Grupo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
