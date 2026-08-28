import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/session_service.dart';
import '../theme/app_theme.dart';
import '../core/config/app_config.dart';

class CreateTicketScreen extends StatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String _selectedCategory = 'bug';
  String _selectedSubcategory = '';
  final _descController = TextEditingController();
  final _fakeProfileController = TextEditingController();
  
  bool _consentReview = false;
  bool _consentTruth = false;
  bool _isSubmitting = false;
  
  XFile? _evidenceImage;
  final _picker = ImagePicker();

  final Map<String, List<String>> _subcategories = {
    'bug': ['La app se cierra', 'Error al subir video', 'Problemas de red', 'Otro error técnico'],
    'fraud': ['Falsificación de Identidad', 'Robo de contenido', 'Estafa o Spam', 'Pagos no reconocidos'],
    'support': ['Problema con mi cuenta', 'Dudas sobre retiros', 'Cambio de datos', 'Otro'],
  };

  @override
  void initState() {
    super.initState();
    _selectedSubcategory = _subcategories[_selectedCategory]!.first;
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _evidenceImage = picked);
    }
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedSubcategory == 'Falsificación de Identidad' && _fakeProfileController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa el enlace al perfil falso.')),
      );
      return;
    }

    if (!_consentReview || !_consentTruth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aceptar las casillas de verificación para continuar.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String evidenceUrl = "";
      if (_evidenceImage != null) {
        final bytes = await _evidenceImage!.readAsBytes();
        final fileExt = _evidenceImage!.path.split('.').last;
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        
        await Supabase.instance.client.storage
            .from('tickets_evidence')
            .uploadBinary(fileName, bytes);
            
        evidenceUrl = Supabase.instance.client.storage
            .from('tickets_evidence')
            .getPublicUrl(fileName);
      }

      final token = await SessionService.getSessionToken();
      
      String structuredMessage = """
**Subcategoría:** $_selectedSubcategory
**Consentimiento de revisión:** Sí
**Declaración de veracidad:** Sí
""";

      if (_selectedSubcategory == 'Falsificación de Identidad') {
        structuredMessage += "**Enlace al perfil falso:** ${_fakeProfileController.text.trim()}\n";
      }

      structuredMessage += "\n**Descripción detallada:**\n${_descController.text.trim()}\n";

      final body = json.encode({
        "subject": "Reporte: $_selectedSubcategory",
        "ticket_type": _selectedCategory,
        "priority": "medium", 
        "message": structuredMessage,
        "evidence_url": evidenceUrl
      });

      final response = await http.post(
        AppConfig.apiUri('/api/v1/support/ticket'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: body,
      );

      if (response.statusCode == 201) {
        if (!mounted) return;
        Navigator.pop(context, true); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reporte enviado correctamente')));
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al enviar el reporte: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Nuevo Reporte', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('¿Qué tipo de problema tienes?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(color: Colors.white),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'bug', child: Text('Reportar un Bug / Fallo técnico')),
                    DropdownMenuItem(value: 'fraud', child: Text('Reportar Fraude / Abuso')),
                    DropdownMenuItem(value: 'support', child: Text('Soporte General / Cuenta')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCategory = val;
                        _selectedSubcategory = _subcategories[val]!.first;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text('Especifica el problema:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedSubcategory,
                  dropdownColor: AppTheme.surface,
                  style: const TextStyle(color: Colors.white),
                  isExpanded: true,
                  items: _subcategories[_selectedCategory]!.map((String sub) {
                    return DropdownMenuItem(value: sub, child: Text(sub));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedSubcategory = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_selectedSubcategory == 'Falsificación de Identidad') ...[
              const Text('Enlace al perfil falso', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _fakeProfileController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'https://...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: AppTheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Por favor ingresa el enlace' : null,
              ),
              const SizedBox(height: 24),
            ],

            const Text('Descripción detallada', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              style: const TextStyle(color: Colors.white),
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Explica exactamente qué sucedió, cuándo y dónde...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              validator: (val) => val == null || val.length < 10 ? 'Por favor ingresa más detalles' : null,
            ),
            const SizedBox(height: 24),

            const Text('Evidencia (Opcional)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image, color: AppTheme.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _evidenceImage != null ? 'Imagen seleccionada: ${_evidenceImage!.name}' : 'Adjuntar captura de pantalla',
                        style: TextStyle(color: _evidenceImage != null ? Colors.white : Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_evidenceImage != null)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                        onPressed: () => setState(() => _evidenceImage = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            CheckboxListTile(
              value: _consentReview,
              onChanged: (val) => setState(() => _consentReview = val ?? false),
              title: const Text('Autorizo al equipo de soporte a revisar los registros de mi cuenta para investigar este caso.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              activeColor: AppTheme.accent,
              checkColor: Colors.white,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _consentTruth,
              onChanged: (val) => setState(() => _consentTruth = val ?? false),
              title: const Text('Confirmo que la información proporcionada es verídica.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              activeColor: AppTheme.accent,
              checkColor: Colors.white,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitTicket,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: _isSubmitting 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Enviar Reporte', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
