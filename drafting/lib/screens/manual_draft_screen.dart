import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/services/native_service.dart';
import '../shared/mixins/draft_analyzer_state_mixin.dart';
import '../shared/mixins/localized_state_mixin.dart';
import '../shared/widgets/champion_picker_sheet.dart';
import '../theme/app_theme.dart';

class ManualDraftScreen extends StatefulWidget {
  final int availableQueries;
  final VoidCallback onDataChanged;
  final VoidCallback onNoQueries;
  final String initialRole;
  final String? initialMyChampion;
  final String modelTier;

  const ManualDraftScreen({
    super.key,
    required this.availableQueries,
    required this.onDataChanged,
    required this.onNoQueries,
    this.initialRole = 'Mid',
    this.initialMyChampion,
    this.modelTier = 'local',
  });

  @override
  State<ManualDraftScreen> createState() => _ManualDraftScreenState();
}

class _ManualDraftScreenState extends State<ManualDraftScreen>
    with LocalizedStateMixin<ManualDraftScreen>, DraftAnalyzerStateMixin<ManualDraftScreen> {
  late String _selectedRole;
  bool _isOtpMode = false;
  String? _myChampion;
  String? _enemyChampion;
  final String _gameMode = 'wild_rift'; // 'wild_rift' o 'lol_pc'

  final List<Map<String, dynamic>> _roles = [
    {'id': 'Top', 'name': 'Solo / Top', 'icon': Icons.shield_outlined},
    {'id': 'Jungle', 'name': 'Jungla', 'icon': Icons.park_outlined},
    {'id': 'Mid', 'name': 'Mid', 'icon': Icons.bolt_rounded},
    {'id': 'ADC', 'name': 'Dúo / ADC', 'icon': Icons.crisis_alert_rounded},
    {'id': 'Support', 'name': 'Soporte', 'icon': Icons.favorite_border_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.initialRole;
    if (widget.initialMyChampion != null && widget.initialMyChampion!.trim().isNotEmpty) {
      _myChampion = widget.initialMyChampion!.trim();
      _isOtpMode = true;
    }
  }

  Future<void> _consultStrategy({bool isRefresh = false}) async {
    if (isAnalyzing) return;

    final bool isLocalMode = widget.modelTier == 'local';

    if (!isLocalMode && widget.availableQueries <= 0) {
      widget.onNoQueries();
      return;
    }

    if (_enemyChampion == null || _enemyChampion!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.hextechCrimson,
          behavior: SnackBarBehavior.floating,
          content: Text('Por favor selecciona el campeón rival de tu línea.'),
        ),
      );
      return;
    }

    if (_isOtpMode && (_myChampion == null || _myChampion!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.hextechCrimson,
          behavior: SnackBarBehavior.floating,
          content: Text('Selecciona tu campeón para recibir la build y runas anti-matchup.'),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    // Modo Local (Tarea 3.3): 100% offline en el procesador del celular, costo $0 e ilimitado
    if (isLocalMode) {
      setState(() {
        isAnalyzing = true;
        isRefreshing = isRefresh;
        errorMessage = null;
      });
      try {
        final res = await NativeService.analyzeLocalDraft(
          role: _selectedRole,
          enemies: [_enemyChampion!.trim()],
          otp: _isOtpMode ? (_myChampion ?? '').trim() : '',
          exclude: isRefresh ? List<String>.from(seenChampions) : const [],
          language: lang.currentLanguage,
        );
        final rec = (res['recommendation'] ?? 'Sin recomendación clara.').toString();
        if (mounted) {
          extractSeenChampions(rec);
          setState(() {
            recommendationText = rec;
            isAnalyzing = false;
            isRefreshing = false;
          });
          HapticFeedback.lightImpact();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            isAnalyzing = false;
            isRefreshing = false;
            errorMessage = 'Error en motor local: $e';
          });
        }
      }
      return;
    }

    final bodyData = <String, dynamic>{
      'main_role': _selectedRole,
      'enemy_champion': _enemyChampion,
      'my_champion': _isOtpMode ? (_myChampion ?? '') : '',
      'game_mode': _gameMode,
      'language': lang.currentLanguage,
    };

    await runDraftAnalysisRequest(
      endpoint: '/draft/manual',
      bodyData: bodyData,
      availableQueries: widget.availableQueries,
      onDataChanged: widget.onDataChanged,
      onNoQueries: widget.onNoQueries,
      isRefresh: isRefresh,
      connectionErrorPrefix: 'Error de conexión',
      lightHapticOnSuccess: true,
    );
  }

  void _showChampionPickerModal({required bool isMyChampion}) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChampionPickerSheet(
        title: isMyChampion ? 'Elige tu Campeón (Tu Pick)' : 'Elige el Rival de tu Línea',
        selectedChampion: isMyChampion ? _myChampion : _enemyChampion,
        onSelected: (champ) {
          setState(() {
            if (isMyChampion) {
              _myChampion = champ;
            } else {
              _enemyChampion = champ;
            }
            resetAnalysisState();
          });
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepDarkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app_rounded, color: AppTheme.hextechCyan, size: 20),
            const SizedBox(width: 8),
            Text(
              'Modo Manual Táctico',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.hextechCyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.hextechCyan.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded, color: AppTheme.hextechCyan, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${widget.availableQueries}',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner 100% Seguro / Anti-Ban
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.hextechEmerald.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.hextechEmerald.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: AppTheme.hextechEmerald, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '100% Seguro: No captura pantalla ni accede a los archivos de Riot.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF6EE7B7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 1. Selector de Línea / Rol
            Text(
              '1. SELECCIONA TU ROL EN LA PARTIDA',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _roles.map((r) {
                  final isSelected = _selectedRole.toLowerCase().contains(r['id'].toString().toLowerCase()) ||
                      r['id'] == _selectedRole;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedRole = r['id'];
                          recommendationText = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.hextechCyan.withValues(alpha: 0.15)
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? AppTheme.hextechCyan : Colors.white10,
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.hextechCyan.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              r['icon'] as IconData,
                              size: 16,
                              color: isSelected ? AppTheme.hextechCyan : Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              r['name'] as String,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected ? Colors.white : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            // 2. Selector de Modo: Counter-pick vs OTP / Ya tengo campeón
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isOtpMode = false);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_isOtpMode ? AppTheme.hextechCyan.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: !_isOtpMode ? Border.all(color: AppTheme.hextechCyan) : null,
                        ),
                        child: Center(
                          child: Text(
                            'Buscar Counter Pick',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: !_isOtpMode ? FontWeight.w800 : FontWeight.w500,
                              color: !_isOtpMode ? Colors.white : Colors.white60,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isOtpMode = true);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _isOtpMode ? AppTheme.hextechGold.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: _isOtpMode ? Border.all(color: AppTheme.hextechGold) : null,
                        ),
                        child: Center(
                          child: Text(
                            'Modo OTP (Mi Campeón)',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: _isOtpMode ? FontWeight.w800 : FontWeight.w500,
                              color: _isOtpMode ? const Color(0xFFFDE047) : Colors.white60,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 3. Tarjetas de Selección de Campeones
            Row(
              children: [
                // Mi campeón (solo si modo OTP activo)
                if (_isOtpMode) ...[
                  Expanded(
                    child: _buildChampionCard(
                      label: 'MI CAMPEÓN (OTP)',
                      championName: _myChampion,
                      accentColor: AppTheme.hextechGold,
                      icon: Icons.person_rounded,
                      onTap: () => _showChampionPickerModal(isMyChampion: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // Campeón Rival (obligatorio siempre)
                Expanded(
                  child: _buildChampionCard(
                    label: 'RIVAL DE LÍNEA',
                    championName: _enemyChampion,
                    accentColor: AppTheme.hextechCrimson,
                    icon: Icons.local_fire_department_rounded,
                    onTap: () => _showChampionPickerModal(isMyChampion: false),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            // Botón de Análisis Principal
            ElevatedButton(
              onPressed: isAnalyzing ? null : () => _consultStrategy(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.hextechCyan,
                foregroundColor: AppTheme.deepDarkBg,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: AppTheme.hextechCyan.withValues(alpha: 0.4),
              ),
              child: isAnalyzing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppTheme.deepDarkBg,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isRefreshing ? 'Buscando alternativas...' : 'Analizando estrategia táctica...',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bolt_rounded, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          _isOtpMode ? 'OBTENER BUILD & RUNAS ANTI-RIVAL' : 'OBTENER MEJOR COUNTER',
                          style: GoogleFonts.outfit(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
            ),

            if (errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.hextechCrimson.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.hextechCrimson),
                ),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                ),
              ),
            ],

            // 4. Resultado del Análisis
            if (recommendationText != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.hextechCyan.withValues(alpha: 0.35)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.hextechCyan.withValues(alpha: 0.2),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.hextechCyan, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'RECOMENDACIÓN TÁCTICA',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.hextechCyan,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                          tooltip: 'Copiar texto',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: recommendationText!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('¡Estrategia copiada al portapapeles!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 24),
                    SelectableText(
                      recommendationText!,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Botón para refrescar y pedir otro campeón
                    if (!_isOtpMode)
                      OutlinedButton.icon(
                        onPressed: isAnalyzing ? null : () => _consultStrategy(isRefresh: true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.hextechCyan,
                          side: const BorderSide(color: AppTheme.hextechCyan),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Ver otras opciones de campeón',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChampionCard({
    required String label,
    required String? championName,
    required Color accentColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final hasChampion = championName != null && championName.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasChampion ? accentColor : Colors.white12,
            width: hasChampion ? 1.5 : 1,
          ),
          boxShadow: hasChampion
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.15),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accentColor, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              hasChampion ? championName : 'Toca para elegir',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: hasChampion ? Colors.white : Colors.white38,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
