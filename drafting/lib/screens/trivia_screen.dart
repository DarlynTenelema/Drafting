import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/trivia_models.dart';
import '../core/services/api_client.dart';
import '../shared/mixins/localized_state_mixin.dart';
import '../shared/widgets/champion_avatar.dart';
import '../shared/widgets/hextech_ui.dart';
import '../theme/app_theme.dart';

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

class _TriviaScreenState extends State<TriviaScreen>
    with SingleTickerProviderStateMixin, LocalizedStateMixin<TriviaScreen> {
  int _triviaLives = 5;
  int _maxDailyLives = 5;
  int _nextRechargeSeconds = 0;
  Timer? _rechargeTimer;

  String _selectedCategory = 'item_cost'; // item_cost, build_path, counter, power_spike, level_duel, best_rune, best_item
  bool _isLoadingQuestion = false;
  bool _isSubmitting = false;
  bool _completedAll = false;
  String _completionMessage = '';

  TriviaQuestion? _currentQuestion;
  String? _selectedOption;
  final TextEditingController _costController = TextEditingController();

  // Feedback tras responder
  bool? _lastAnswerCorrect;
  String? _correctAnswerFeedback;
  String? _explanationFeedback;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _loadNextQuestion();
  }

  @override
  void dispose() {
    _rechargeTimer?.cancel();
    _costController.dispose();
    super.dispose();
  }

  void _syncRechargeTimer(int seconds) {
    _rechargeTimer?.cancel();
    _nextRechargeSeconds = seconds > 0 ? seconds : 0;
    if (_nextRechargeSeconds <= 0) return;

    _rechargeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_nextRechargeSeconds <= 1) {
        timer.cancel();
        setState(() => _nextRechargeSeconds = 0);
        _fetchStatus();
      } else {
        setState(() => _nextRechargeSeconds--);
      }
    });
  }

  String _formatRechargeCountdown() {
    if (_nextRechargeSeconds <= 0) return 'Listo';
    final hours = _nextRechargeSeconds ~/ 3600;
    final minutes = (_nextRechargeSeconds % 3600) ~/ 60;
    final secs = _nextRechargeSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
  }

  Future<void> _fetchStatus() async {
    try {
      final res = await ApiClient.get('/trivia/status', authenticated: true);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          final nextSecs = (data['next_recharge_seconds'] as num?)?.toInt() ?? 0;
          setState(() {
            _triviaLives = (data['trivia_lives'] as num?)?.toInt() ?? 5;
            _maxDailyLives = (data['max_daily_lives'] as num?)?.toInt() ?? 5;
          });
          _syncRechargeTimer(nextSecs);
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
      _explanationFeedback = null;
      _completedAll = false;
    });

    try {
      final res = await ApiClient.get(
        '/trivia/question?category=$_selectedCategory',
        authenticated: true,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (mounted) {
          final nextSecs = (data['next_recharge_seconds'] as num?)?.toInt() ?? _nextRechargeSeconds;
          setState(() {
            _triviaLives = (data['trivia_lives'] as num?)?.toInt() ?? _triviaLives;
            _maxDailyLives = (data['max_daily_lives'] as num?)?.toInt() ?? _maxDailyLives;
            if (data['completed_all'] == true) {
              _completedAll = true;
              _completionMessage = data['message'] ?? '¡Has completado todas las preguntas de esta modalidad!';
            } else {
              _currentQuestion = TriviaQuestion.fromJson(data, fallbackCategory: _selectedCategory);
            }
            _isLoadingQuestion = false;
          });
          _syncRechargeTimer(nextSecs);
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
          'question_id': _currentQuestion!.id,
          'user_answer': trimmedAns,
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final bool isCorrect = data['is_correct'] ?? false;
        final int newLives = (data['trivia_lives'] as num?)?.toInt() ?? _triviaLives;
        final int nextSecs = (data['next_recharge_seconds'] as num?)?.toInt() ?? _nextRechargeSeconds;

        if (mounted) {
          final String expl = (data['explanation'] ?? '').toString().trim();
          setState(() {
            _lastAnswerCorrect = isCorrect;
            _correctAnswerFeedback = data['correct_answer']?.toString();
            _explanationFeedback = expl.isNotEmpty ? expl : null;
            _triviaLives = newLives;
            _isSubmitting = false;
          });
          _syncRechargeTimer(nextSecs);

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
        try {
          final data = jsonDecode(res.body);
          final nextSecs = (data['next_recharge_seconds'] as num?)?.toInt() ?? _nextRechargeSeconds;
          _syncRechargeTimer(nextSecs);
        } catch (_) {}
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
    final countdown = _nextRechargeSeconds > 0
        ? _formatRechargeCountdown()
        : '24 horas';
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.hextechCrimson, width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.heart_broken_rounded, color: AppTheme.hextechCrimson, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('trivia_no_lives_title'),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Te quedaste sin vidas por hoy. Tus $_maxDailyLives vidas se recargan gratis automáticamente cada día.',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.hextechCyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.hextechCyan.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: AppTheme.hextechCyan, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Próxima recarga gratis en: $countdown',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.hextechCyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (!widget.isTab && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showLivesRechargeSheet() {
    final bool isFull = _triviaLives >= _maxDailyLives;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
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
                const HextechSheetHandle(),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite_rounded, color: AppTheme.hextechCrimson, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Tienes $_triviaLives / $_maxDailyLives vidas',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (isFull ? AppTheme.hextechEmerald : AppTheme.hextechCyan)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isFull ? Icons.check_circle_rounded : Icons.schedule_rounded,
                        color: isFull ? AppTheme.hextechEmerald : AppTheme.hextechCyan,
                        size: 26,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isFull
                                  ? 'Vidas al máximo'
                                  : 'Recarga diaria gratuita',
                              style: GoogleFonts.outfit(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isFull
                                  ? 'Tienes todas tus vidas listas para jugar hoy sin anuncios.'
                                  : 'Tus $_maxDailyLives vidas se recargan gratis en ${_formatRechargeCountdown()}. ¡Vuelve mañana para seguir jugando!',
                              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
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
        backgroundColor: AppTheme.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkScaffold,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isTab,
        title: Text(
          tr('trivia_appbar'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          // Contador de Vidas + Recarga Diaria Gratuita
          InkWell(
            onTap: _showLivesRechargeSheet,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.hextechCrimson.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.hextechCrimson.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_rounded, color: AppTheme.hextechCrimson, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '$_triviaLives/$_maxDailyLives',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  if (_nextRechargeSeconds > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      _formatRechargeCountdown(),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.hextechCyan,
                      ),
                    ),
                  ],
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
                      child: CircularProgressIndicator(color: AppTheme.hextechCyan),
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
    final categories = [
      (
        id: 'item_cost',
        title: tr('trivia_tab_cost'),
        icon: Icons.monetization_on_rounded,
        color: const Color(0xFFFBBF24),
      ),
      (
        id: 'build_path',
        title: tr('trivia_tab_build'),
        icon: Icons.alt_route_rounded,
        color: AppTheme.hextechCyan,
      ),
      (
        id: 'counter',
        title: tr('trivia_tab_counter'),
        icon: Icons.shield_rounded,
        color: const Color(0xFFF43F5E),
      ),
      (
        id: 'power_spike',
        title: tr('trivia_tab_power_spike'),
        icon: Icons.bolt_rounded,
        color: const Color(0xFFA855F7),
      ),
      (
        id: 'level_duel',
        title: tr('trivia_tab_level_duel'),
        icon: Icons.sports_mma_rounded,
        color: const Color(0xFFFB923C),
      ),
      (
        id: 'best_rune',
        title: tr('trivia_tab_best_rune'),
        icon: Icons.auto_awesome_rounded,
        color: AppTheme.hextechEmerald,
      ),
      (
        id: 'best_item',
        title: tr('trivia_tab_best_item'),
        icon: Icons.diamond_rounded,
        color: const Color(0xFF38BDF8),
      ),
    ];

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final cat = categories[idx];
          return _buildCategoryTabItem(
            id: cat.id,
            title: cat.title,
            icon: cat.icon,
            accentColor: cat.color,
          );
        },
      ),
    );
  }

  Widget _buildCategoryTabItem({
    required String id,
    required String title,
    required IconData icon,
    required Color accentColor,
  }) {
    final bool isSelected = _selectedCategory == id;
    return InkWell(
      onTap: () {
        if (_selectedCategory != id) {
          setState(() {
            _selectedCategory = id;
          });
          _loadNextQuestion();
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 96),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.18)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? accentColor
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? accentColor : Colors.white60,
              size: 19,
            ),
            const SizedBox(height: 3),
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
    );
  }

  Widget _buildCluePill(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTargetCardBody(TriviaQuestion q) {
    final targetName = q.targetName;
    final clues = q.clues;

    if (q.isItemCost) {
      return Column(
        children: [
          const Icon(Icons.inventory_2_rounded, color: Color(0xFFFBBF24), size: 42),
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
          if (clues.isNotEmpty) _buildCluePill(clues, const Color(0xFFFBBF24)),
          const SizedBox(height: 8),
          Text(
            tr('trivia_write_gold_hint'),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
          ),
        ],
      );
    }

    if (q.isBuildPath) {
      return Column(
        children: [
          const Icon(Icons.account_tree_rounded, color: AppTheme.accent, size: 40),
          const SizedBox(height: 12),
          Text(
            tr('trivia_components_title'),
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
              color: AppTheme.hextechCyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.hextechCyan.withValues(alpha: 0.3)),
            ),
            child: Text(
              clues.isNotEmpty ? clues : targetName,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.hextechCyan,
              ),
            ),
          ),
        ],
      );
    }

    if (q.isCounter) {
      return Column(
        children: [
          ChampionAvatar(
            championName: targetName,
            size: 88,
            borderColor: const Color(0xFFF43F5E),
            borderWidth: 2.5,
          ),
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
          if (clues.isNotEmpty) _buildCluePill(clues, const Color(0xFFF43F5E)),
          const SizedBox(height: 8),
          Text(
            tr('trivia_which_counter_sub'),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
          ),
        ],
      );
    }

    if (q.isPowerSpike) {
      return Column(
        children: [
          ChampionAvatar(
            championName: targetName,
            size: 88,
            borderColor: const Color(0xFFA855F7),
            borderWidth: 2.5,
          ),
          const SizedBox(height: 12),
          Text(
            targetName,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFC084FC),
            ),
          ),
          if (clues.isNotEmpty) _buildCluePill(clues, const Color(0xFFC084FC)),
          const SizedBox(height: 8),
          Text(
            tr('trivia_power_spike_sub'),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
          ),
        ],
      );
    }

    if (q.isLevelDuel) {
      final fighters = q.duelChampions;
      final leftChamp = fighters.isNotEmpty ? fighters[0] : targetName;
      final rightChamp = fighters.length > 1 ? fighters[1] : '';

      return Column(
        children: [
          if (clues.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFB923C).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFB923C), width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flash_on_rounded, color: Color(0xFFFB923C), size: 16),
                  const SizedBox(width: 4),
                  Text(
                    clues,
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFFDBA74),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: Column(
                  children: [
                    ChampionAvatar(
                      championName: leftChamp,
                      size: 76,
                      borderColor: AppTheme.hextechCyan,
                      borderWidth: 2.2,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      leftChamp,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFB923C).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFB923C), width: 1.5),
                ),
                child: Text(
                  'VS',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFFDBA74),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    ChampionAvatar(
                      championName: rightChamp,
                      size: 76,
                      borderColor: const Color(0xFFF43F5E),
                      borderWidth: 2.2,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rightChamp,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tr('trivia_level_duel_sub'),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
          ),
        ],
      );
    }

    if (q.isBestRune) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.hextechEmerald.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.hextechEmerald, width: 1.8),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppTheme.hextechEmerald,
              size: 38,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            targetName,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: AppTheme.hextechEmerald,
            ),
          ),
          if (clues.isNotEmpty) _buildCluePill(clues, AppTheme.hextechEmerald),
          const SizedBox(height: 8),
          Text(
            tr('trivia_best_rune_sub'),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
          ),
        ],
      );
    }

    // best_item (y fallback general)
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.8),
          ),
          child: const Icon(
            Icons.diamond_rounded,
            color: Color(0xFF38BDF8),
            size: 38,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          targetName,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF38BDF8),
          ),
        ),
        if (clues.isNotEmpty) _buildCluePill(clues, const Color(0xFF38BDF8)),
        const SizedBox(height: 8),
        Text(
          tr('trivia_best_item_sub'),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _buildQuestionContent() {
    final q = _currentQuestion!;
    final options = q.options;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pregunta Superior
          Text(
            q.questionText,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Tarjeta Central del Objetivo (Objeto / Campeón / Duelo VS / Runa)
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  AppTheme.surface,
                  AppTheme.background,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.hextechCyan.withValues(alpha: 0.3),
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
            child: _buildTargetCardBody(q),
          ),

          const SizedBox(height: 24),

          // Feedback de Respuesta (Si ya contestó)
          if (_lastAnswerCorrect != null) _buildFeedbackBanner(),

          // Si aún no ha respondido: Formulario según Categoría
          if (_lastAnswerCorrect == null) ...[
            if (q.isItemCost) ...[
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
                  fillColor: AppTheme.surface,
                ),
                onSubmitted: (val) => _submitAnswer(val),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSubmitting ? null : () => _submitAnswer(_costController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.hextechEmerald,
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
                        tr('trivia_verify_btn'),
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ] else ...[
              // Opciones Múltiples (A, B, C, D)
              ...options.asMap().entries.map((entry) {
                final int idx = entry.key;
                final String opt = entry.value;
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
                            ? AppTheme.hextechCyan.withValues(alpha: 0.15)
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.hextechCyan
                              : Colors.white.withValues(alpha: 0.1),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (q.optionsAreChampions) ...[
                            ChampionAvatar(
                              championName: opt,
                              size: 42,
                              borderColor: isSelected
                                  ? AppTheme.hextechCyan
                                  : Colors.white24,
                              borderWidth: 1.5,
                            ),
                            const SizedBox(width: 12),
                          ] else ...[
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.hextechCyan : Colors.white12,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                letter,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? AppTheme.deepDarkBg : Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                          ],
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
                          if (q.optionsAreChampions)
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.hextechCyan : Colors.white10,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                letter,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? AppTheme.deepDarkBg : Colors.white60,
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
                backgroundColor: AppTheme.hextechCyan,
                foregroundColor: AppTheme.deepDarkBg,
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
    final color = isCorrect ? AppTheme.hextechEmerald : AppTheme.hextechCrimson;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_explanationFeedback != null && _explanationFeedback!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.hextechCyan.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.lightbulb_rounded,
                      color: Color(0xFFFBBF24),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('trivia_why_title'),
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFFBBF24),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _explanationFeedback!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
                color: AppTheme.hextechAmber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.hextechAmber, width: 2),
              ),
              child: const Icon(Icons.emoji_events_rounded, color: AppTheme.hextechAmber, size: 64),
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
                backgroundColor: AppTheme.hextechCyan,
                foregroundColor: AppTheme.deepDarkBg,
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
