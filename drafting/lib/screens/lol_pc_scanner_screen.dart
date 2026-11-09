import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/services/api_client.dart';
import '../core/services/language_service.dart';
import '../theme/app_theme.dart';

class LolPcScannerScreen extends StatefulWidget {
  final int availableQueries;
  final VoidCallback onDataChanged;
  final VoidCallback onNoQueries;

  const LolPcScannerScreen({
    super.key,
    required this.availableQueries,
    required this.onDataChanged,
    required this.onNoQueries,
  });

  @override
  State<LolPcScannerScreen> createState() => _LolPcScannerScreenState();
}

class _LolPcScannerScreenState extends State<LolPcScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _capturedImage;
  bool _isAnalyzing = false;
  String? _recommendationText;

  // Preferencia de Rol
  String _selectedRole = 'Auto';
  final List<String> _availableRoles = ['Auto', 'Top', 'Jungle', 'Mid', 'ADC', 'Support'];

  Future<void> _takePhoto() async {
    if (widget.availableQueries <= 0) {
      widget.onNoQueries();
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 82,
      );

      if (photo != null) {
        setState(() {
          _capturedImage = File(photo.path);
          _recommendationText = null;
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LanguageService.instance.tr('pc_scanner_camera_error', {'error': '$e'})),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _analyzePhoto() async {
    if (_capturedImage == null || _isAnalyzing) return;

    if (widget.availableQueries <= 0) {
      widget.onNoQueries();
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _recommendationText = null;
    });

    try {
      final bytes = await _capturedImage!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final lang = LanguageService.instance.currentLanguage;

      final res = await ApiClient.post(
        '/draft/analyze',
        authenticated: true,
        body: {
          'image_base64': base64Image,
          'main_role': _selectedRole,
          'secondary_role': 'Auto',
          'autofill_role': 'Auto',
          'game_mode': 'lol_pc',
          'language': lang,
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _recommendationText = data['recommendation'] ?? 'Sin recomendación clara.';
            _isAnalyzing = false;
          });
          widget.onDataChanged();
          HapticFeedback.mediumImpact();
        }
      } else if (res.statusCode == 402) {
        if (mounted) {
          setState(() => _isAnalyzing = false);
          widget.onNoQueries();
        }
      } else {
        if (mounted) {
          setState(() => _isAnalyzing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error del servidor (${res.statusCode}): ${res.body}'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión al analizar: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.computer_rounded, color: Color(0xFF38BDF8), size: 22),
            const SizedBox(width: 8),
            Text(
              lang.tr('pc_scanner_title'),
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Banner Explicativo
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0284C7).withValues(alpha: 0.18),
                      const Color(0xFF0369A1).withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.photo_camera_rounded, color: Color(0xFF38BDF8), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lang.tr('pc_scanner_banner_title'),
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lang.tr('pc_scanner_banner_sub'),
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Selector de Rol
              Text(
                lang.tr('pc_scanner_role_label'),
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _availableRoles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, idx) {
                    final role = _availableRoles[idx];
                    final bool isSelected = _selectedRole == role;
                    return ChoiceChip(
                      label: Text(role),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedRole = role);
                      },
                      selectedColor: const Color(0xFF00E5FF),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isSelected ? const Color(0xFF090D16) : Colors.white70,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF00E5FF) : Colors.white12,
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Contenedor de la Imagen / Botón de Captura
              if (_capturedImage == null) ...[
                InkWell(
                  onTap: _takePhoto,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: 260,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                        width: 1.5,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Color(0xFF00E5FF),
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          lang.tr('pc_scanner_take_photo'),
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          lang.tr('pc_scanner_take_photo_hint'),
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Vista Previa de la Foto Capturada
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Image.file(
                        _capturedImage!,
                        height: 260,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: ElevatedButton.icon(
                          onPressed: _isAnalyzing ? null : _takePhoto,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(lang.tr('pc_scanner_retake_photo')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: 0.7),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Botón de Analizar Selección
                ElevatedButton.icon(
                  onPressed: _isAnalyzing ? null : _analyzePhoto,
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    _isAnalyzing ? lang.tr('pc_scanner_analyzing') : lang.tr('pc_scanner_analyze_btn'),
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Resultado de la Recomendación
              if (_recommendationText != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1E293B),
                        const Color(0xFF0F172A),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 24),
                          const SizedBox(width: 8),
                          Text(
                            lang.tr('pc_scanner_rec_title'),
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 24),
                      SelectableText(
                        _recommendationText!,
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          height: 1.55,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          height: 1.55,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

