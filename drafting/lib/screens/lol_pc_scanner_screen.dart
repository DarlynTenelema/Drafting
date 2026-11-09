import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/services/api_client.dart';
import '../core/services/language_service.dart';

class LolPcScannerScreen extends StatefulWidget {
  final File initialImage;
  final int availableQueries;
  final VoidCallback onDataChanged;
  final VoidCallback onNoQueries;

  const LolPcScannerScreen({
    super.key,
    required this.initialImage,
    required this.availableQueries,
    required this.onDataChanged,
    required this.onNoQueries,
  });

  @override
  State<LolPcScannerScreen> createState() => _LolPcScannerScreenState();
}

class _LolPcScannerScreenState extends State<LolPcScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  late File _capturedImage;
  bool _isAnalyzing = false;
  String? _recommendationText;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _capturedImage = widget.initialImage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analyzePhoto();
    });
  }

  Future<void> _takeNewPhotoAndAnalyze() async {
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
          _errorMessage = null;
        });
        HapticFeedback.lightImpact();
        await _analyzePhoto();
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
    if (_isAnalyzing) return;

    if (widget.availableQueries <= 0) {
      widget.onNoQueries();
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _recommendationText = null;
      _errorMessage = null;
    });

    try {
      final bytes = await _capturedImage.readAsBytes();
      final base64Image = base64Encode(bytes);
      final lang = LanguageService.instance.currentLanguage;

      final res = await ApiClient.post(
        '/draft/analyze',
        authenticated: true,
        body: {
          'image_base64': base64Image,
          'main_role': 'Auto',
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
          setState(() {
            _isAnalyzing = false;
            _errorMessage = 'Error del servidor (${res.statusCode}): ${res.body}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _errorMessage = 'Error de conexión al analizar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B111E),
        elevation: 0,
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
              // Vista Previa de la Pantalla PC capturada
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isAnalyzing
                        ? const Color(0xFF38BDF8)
                        : Colors.white.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                  boxShadow: _isAnalyzing
                      ? [
                          BoxShadow(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.file(
                        _capturedImage,
                        height: 190,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        height: 190,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.2),
                              Colors.black.withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                      ),
                      if (_isAnalyzing)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 42,
                              height: 42,
                              child: CircularProgressIndicator(
                                color: Color(0xFF38BDF8),
                                strokeWidth: 3.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF090D16).withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                lang.tr('pc_scanner_analyzing'),
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Contenedor de Error si falla
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEF4444)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: _analyzePhoto,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: Text(lang.tr('pc_scanner_retry_btn')),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF38BDF8)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Resultado de la Recomendación Challenger
              if (_recommendationText != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF162032),
                        Color(0xFF0B111E),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              lang.tr('pc_scanner_rec_title'),
                              style: GoogleFonts.outfit(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 24),
                      SelectableText(
                        _recommendationText!,
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          height: 1.58,
                          color: Colors.white.withValues(alpha: 0.94),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Botones de Acción (Escanear de Nuevo & Volver)
              ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _takeNewPhotoAndAnalyze,
                icon: const Icon(Icons.camera_alt_rounded, size: 20),
                label: Text(
                  lang.tr('pc_scanner_rescan_btn'),
                  style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
              ),

              const SizedBox(height: 10),

              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  lang.tr('pc_scanner_finish_btn'),
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
