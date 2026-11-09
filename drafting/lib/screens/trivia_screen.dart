import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/services/ad_service.dart';
import '../core/services/api_client.dart';
import '../core/services/language_service.dart';
import '../theme/app_theme.dart';
import 'store_screen.dart';

class TriviaScreen extends StatefulWidget {
  final VoidCallback? onLivesChanged;
  final bool isTab;

  const TriviaScreen({
    super.key,
    this.onLivesChanged,
    this.isTab = false,
  });

  @override
  State<TriviaScreen> createState() => _TriviaScreenState();
}

class _TriviaScreenState extends State<TriviaScreen> with SingleTickerProviderStateMixin {
  int _triviaLives = 5;
  String _selectedCategory = 'item_cost'; // 'item_cost', 'build_path', 'counter'
  bool _isLoadingQuestion = false;
  bool _isSubmitting = false;
  bool _isRewardingAd = false;
  bool _completedAll = false;
  String _completionMessage = '';

  Map<String, dynamic>? _currentQuestion;
  String? _selectedOption;
  final TextEditingController _costController = TextEditingController();

  // Feedback tras responder
  bool? _lastAnswerCorrect;
  String? _correctAnswerFeedback;
  String? _feedbackMessage;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _loadNextQuestion();
  }

  @override
  void dispose() {
    _costController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      final res = await ApiClient.get('/trivia/status', authenticated: true);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _triviaLives = data['trivia_lives'] ?? 5;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadNextQuestion() async {
    setState(() {
      _isLoadingQuestion = true;
      _currentQuestion = null;
      _selectedOption = null;
      _costController.clear();
      _lastAnswerCorrect = null;
      _correctAnswerFeedback = null;
      _feedbackMessage = null;
      _completedAll = false;
    });

    try {
      final res = await ApiClient.get(
        '/trivia/question?category=$_selectedCategory',
        authenticated: true,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _triviaLives = data['trivia_lives'] ?? _triviaLives;
            if (data['completed_all'] == true) {
              _completedAll = true;
              _completionMessage = data['message'] ?? '¡Has completado todas las preguntas de esta modalidad!';
            } else {
              _currentQuestion = data;
            }
            _isLoadingQuestion = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingQuestion = false);
          _showSnackBar('No se pudo cargar la pregunta. Código ${res.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingQuestion = false);
        _showSnackBar('Error de conexión al cargar pregunta.');
      }
    }
  }

  Future<void> _submitAnswer(String answer) async {
    if (_currentQuestion == null || _isSubmitting) return;

    if (_triviaLives <= 0) {
      _showNoLivesDialog();
      return;
    }

    final trimmedAns = answer.trim();
    if (trimmedAns.isEmpty) {
      _showSnackBar('Por favor ingresa o selecciona una respuesta.');
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final res = await ApiClient.post(
        '/trivia/answer',
        authenticated: true,
        body: {
          'question_id': _currentQuestion!['id'],
          'user_answer': trimmedAns,
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final bool isCorrect = data['is_correct'] ?? false;
        final int newLives = data['trivia_lives'] ?? _triviaLives;

        if (mounted) {
          setState(() {
            _lastAnswerCorrect = isCorrect;
            _correctAnswerFeedback = data['correct_answer'];
            _feedbackMessage = data['message'];
            _triviaLives = newLives;
            _isSubmitting = false;
          });

          widget.onLivesChanged?.call();

          if (isCorrect) {
            HapticFeedback.lightImpact();
          } else {
            HapticFeedback.heavyImpact();
            if (_triviaLives <= 0) {
              Future.delayed(const Duration(milliseconds: 600), () {
                if (mounted) _showNoLivesDialog();
              });
            }
          }
        }
      } else if (res.statusCode == 403) {
        setState(() => _isSubmitting = false);
        _showNoLivesDialog();
      } else {
        setState(() => _isSubmitting = false);
        _showSnackBar('Error validando respuesta.');
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      _showSnackBar('Error de red al comprobar respuesta.');
    }
  }

  Future<void> _rewardAdLives() async {
    if (_isRewardingAd) return;
    setState(() => _isRewardingAd = true);

    await AdService.showRewardedAd(
      onUserEarnedReward: () async {
        try {
          final res = await ApiClient.post('/trivia/reward-ad', authenticated: true);
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (mounted) {
              setState(() {
                _triviaLives = data['trivia_lives'] ?? (_triviaLives + 3);
                _isRewardingAd = false;
              });
              widget.onLivesChanged?.call();
              _showSnackBar('¡+3 vidas añadidas con éxito! ❤️❤️❤️');
              if (_currentQuestion == null) {
                _loadNextQuestion();
              }
            }
          } else {
            if (mounted) setState(() => _isRewardingAd = false);
          }
        } catch (_) {
          if (mounted) setState(() => _isRewardingAd = false);
        }
      },
      onAdFailed: (error) {
        if (mounted) {
          setState(() => _isRewardingAd = false);
          _showSnackBar(error);
        }
      },
    );
  }

  Future<void> _resetCategoryProgress() async {
    try {
      final res = await ApiClient.delete(
        '/trivia/progress/reset?category=$_selectedCategory',
        authenticated: true,
      );
      if (res.statusCode == 200) {
        _showSnackBar('Progreso reiniciado. ¡A jugar de nuevo!');
        _loadNextQuestion();
      }
    } catch (_) {
      _showSnackBar('Error al reiniciar el progreso.');
    }
  }

  void _showNoLivesDialog() {
    final lang = LanguageService.instance;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.heart_broken_rounded, color: Color(0xFFEF4444), size: 28),
            const SizedBox(width: 10),
            Text(
              lang.tr('trivia_no_lives_title'),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          lang.tr('trivia_no_lives_msg'),
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context); // Volver al inicio
            },
            child: const Text('Salir', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.storefront_rounded, size: 18),
            label: Text(lang.tr('trivia_store_btn')),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StoreScreen(onDataChanged: _fetchStatus)),
              );
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
            label: Text(lang.tr('trivia_watch_ad_btn')),
            onPressed: () {
              Navigator.pop(ctx);
              _rewardAdLives();
            },
          ),
        ],
      ),
    );
  }

  void _showGetLivesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Tienes $_triviaLives vidas',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Opción 1: Anuncio recompensado
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _rewardAdLives();
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF10B981).withValues(alpha: 0.2),
                          const Color(0xFF059669).withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.ondemand_video_rounded, color: Color(0xFF10B981), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ver anuncio de video',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Gana +3 vidas inmediatamente (Gratis)',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '+3 ❤️',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Opción 2: Paquetes en tienda
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => StoreScreen(onDataChanged: _fetchStatus)),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                          const Color(0xFF6D28D9).withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shopping_bag_rounded, color: Color(0xFFA78BFA), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Comprar packs de vidas',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '20 vidas (\$0.19) • 50 (\$0.49) • 100 (\$0.99)',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isTab,
        title: Text(
          lang.tr('trivia_appbar'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          // Contador de Vidas
          InkWell(
            onTap: _showGetLivesSheet,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '$_triviaLives',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.add_circle_rounded, color: Color(0xFF10B981), size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Selector de Sub-Pantallas / Categorías
            _buildCategoryTabs(),

            // Contenido de la pregunta
            Expanded(
              child: _isLoadingQuestion
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                    )
                  : _completedAll
                      ? _buildCompletedView()
                      : _currentQuestion == null
                          ? _buildEmptyView()
                          : _buildQuestionContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    final lang = LanguageService.instance;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _buildCategoryTabItem(
            id: 'item_cost',
            title: lang.tr('trivia_tab_cost'),
            icon: Icons.monetization_on_rounded,
          ),
          const SizedBox(width: 8),
          _buildCategoryTabItem(
            id: 'build_path',
            title: lang.tr('trivia_tab_build'),
            icon: Icons.alt_route_rounded,
          ),
          const SizedBox(width: 8),
          _buildCategoryTabItem(
            id: 'counter',
            title: lang.tr('trivia_tab_counter'),
            icon: Icons.shield_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabItem({
    required String id,
    required String title,
    required IconData icon,
  }) {
    final bool isSelected = _selectedCategory == id;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (_selectedCategory != id) {
            setState(() {
              _selectedCategory = id;
            });
            _loadNextQuestion();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF00E5FF)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF00E5FF) : Colors.white60,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionContent() {
    final q = _currentQuestion!;
    final category = q['category'] ?? _selectedCategory;
    final questionText = q['question_text'] ?? '';
    final targetName = q['target_name'] ?? '';
    final clues = q['clues'] ?? '';
    final List<dynamic> options = q['options'] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pregunta Superior
          Text(
            questionText,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Tarjeta Central del Objetivo (Objeto / Campeón / Red de Armado)
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1E293B),
                  const Color(0xFF0F172A),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                if (category == 'item_cost') ...[
                  const Icon(Icons.inventory_2_rounded, color: Color(0xFFFBBF24), size: 40),
                  const SizedBox(height: 12),
                  Text(
                    targetName,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFFBBF24),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LanguageService.instance.tr('trivia_write_gold_hint'),
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                  ),
                ] else if (category == 'build_path') ...[
                  const Icon(Icons.account_tree_rounded, color: Color(0xFF38BDF8), size: 40),
                  const SizedBox(height: 12),
                  Text(
                    LanguageService.instance.tr('trivia_components_title'),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      clues.isNotEmpty ? clues : targetName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00E5FF),
                      ),
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.gavel_rounded, color: Color(0xFFF43F5E), size: 40),
                  const SizedBox(height: 12),
                  Text(
                    targetName,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFF43F5E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LanguageService.instance.tr('trivia_which_counter_sub'),
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Feedback de Respuesta (Si ya contestó)
          if (_lastAnswerCorrect != null) _buildFeedbackBanner(),

          // Si aún no ha respondido: Formulario según Categoría
          if (_lastAnswerCorrect == null) ...[
            if (category == 'item_cost') ...[
              // Input Numérico para el Precio
              TextField(
                controller: _costController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'Ej: 3333',
                  prefixIcon: const Icon(Icons.monetization_on_rounded, color: Color(0xFFFBBF24)),
                  suffixText: 'Oro',
                  suffixStyle: GoogleFonts.outfit(color: Colors.white70, fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                ),
                onSubmitted: (val) => _submitAnswer(val),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSubmitting ? null : () => _submitAnswer(_costController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        LanguageService.instance.tr('trivia_verify_btn'),
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ] else ...[
              // Opciones Múltiples (A, B, C, D)
              ...options.asMap().entries.map((entry) {
                final int idx = entry.key;
                final String opt = entry.value.toString();
                final String letter = String.fromCharCode(65 + idx); // A, B, C, D
                final bool isSelected = _selectedOption == opt;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: InkWell(
                    onTap: _isSubmitting
                        ? null
                        : () {
                            setState(() => _selectedOption = opt);
                            _submitAnswer(opt);
                          },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF00E5FF)
                              : Colors.white.withValues(alpha: 0.1),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF00E5FF) : Colors.white12,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              letter,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                color: isSelected ? const Color(0xFF090D16) : Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              opt,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ] else ...[
            // Botón de Siguiente Pregunta
            ElevatedButton.icon(
              onPressed: _loadNextQuestion,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Siguiente Pregunta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF090D16),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeedbackBanner() {
    final bool isCorrect = _lastAnswerCorrect ?? false;
    final color = isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: color,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isCorrect ? '¡Respuesta Correcta!' : '¡Respuesta Incorrecta!',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (!isCorrect && _correctAnswerFeedback != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 38),
                Expanded(
                  child: Text(
                    'La respuesta correcta era: $_correctAnswerFeedback',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF59E0B), width: 2),
              ),
              child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFF59E0B), size: 64),
            ),
            const SizedBox(height: 20),
            Text(
              '¡Completado!',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _completionMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _resetCategoryProgress,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reiniciar modalidad y volver a jugar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF090D16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.quiz_outlined, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(
            'No hay preguntas disponibles',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadNextQuestion,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

