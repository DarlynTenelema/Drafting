import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/services/session_service.dart';
import '../theme/app_theme.dart';
import '../core/config/app_config.dart';

class SuggestionBoxScreen extends StatefulWidget {
  const SuggestionBoxScreen({super.key});

  @override
  State<SuggestionBoxScreen> createState() => _SuggestionBoxScreenState();
}

class _SuggestionBoxScreenState extends State<SuggestionBoxScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String _selectedCategory = 'features';
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  bool _isSubmitting = false;

  final List<Map<String, String>> _categories = [
    {'id': 'ui', 'label': 'Diseño y Visuales', 'icon': '🎨'},
    {'id': 'economy', 'label': 'Economía y Monedas', 'icon': '💰'},
    {'id': 'content', 'label': 'Videos y Arte', 'icon': '🖼️'},
    {'id': 'features', 'label': 'Nuevas Funciones', 'icon': '✨'},
    {'id': 'other', 'label': 'Otro', 'icon': '💡'},
  ];

  Future<void> _submitSuggestion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final token = await SessionService.getSessionToken();
      final body = json.encode({
        "title": _titleController.text.trim(),
        "category": _selectedCategory,
        "description": _descController.text.trim(),
      });

      final response = await http.post(
        AppConfig.apiUri('/api/v1/support/suggestion'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: body,
      );

      if (response.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Gracias por tu idea! La revisaremos pronto.')));
        Navigator.pop(context);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Buzón de Ideas', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.lightbulb, size: 64, color: AppTheme.accent.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(
              'Ayúdanos a mejorar',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Las mejores sugerencias son implementadas por nuestro equipo. ¡Queremos escucharte!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 32),

            const Text('¿Sobre qué es tu idea?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat['id'];
                return ChoiceChip(
                  label: Text('${cat['icon']} ${cat['label']}'),
                  selected: isSelected,
                  selectedColor: AppTheme.accent,
                  backgroundColor: AppTheme.surface,
                  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                  onSelected: (bool selected) {
                    if (selected) setState(() => _selectedCategory = cat['id']!);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            const Text('Resumen', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ej: Modo oscuro para la app',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              validator: (val) => val == null || val.length < 5 ? 'El título es muy corto' : null,
            ),
            const SizedBox(height: 24),

            const Text('Detalles de tu sugerencia', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              style: const TextStyle(color: Colors.white),
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Explica cómo funcionaría y por qué sería útil...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              validator: (val) => val == null || val.length < 10 ? 'Por favor ingresa más detalles' : null,
            ),
            
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitSuggestion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: _isSubmitting 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Enviar Idea', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
