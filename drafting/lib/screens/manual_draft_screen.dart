import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants/app_constants.dart';
import '../core/services/api_client.dart';
import '../core/services/language_service.dart';
import '../theme/app_theme.dart';

class ManualDraftScreen extends StatefulWidget {
  final int availableQueries;
  final VoidCallback onDataChanged;
  final VoidCallback onNoQueries;
  final String initialRole;
  final String? initialMyChampion;

  const ManualDraftScreen({
    super.key,
    required this.availableQueries,
    required this.onDataChanged,
    required this.onNoQueries,
    this.initialRole = 'Mid',
    this.initialMyChampion,
  });

  @override
  State<ManualDraftScreen> createState() => _ManualDraftScreenState();
}

class _ManualDraftScreenState extends State<ManualDraftScreen> {
  late String _selectedRole;
  bool _isOtpMode = false;
  String? _myChampion;
  String? _enemyChampion;
  String _gameMode = 'wild_rift'; // 'wild_rift' o 'lol_pc'

  bool _isAnalyzing = false;
  bool _isRefreshing = false;
  String? _recommendationText;
  String? _errorMessage;
  final List<String> _seenChampions = [];

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

  void _extractSeenChampions(String text) {
    final regA = RegExp(r'(?:PLAN|PLANO)\s*A\s*:\s*([^•\n\r]+)', caseSensitive: false);
    final matchA = regA.firstMatch(text);
    if (matchA != null) {
      final name = matchA.group(1)?.trim();
      if (name != null && name.isNotEmpty && !_seenChampions.contains(name)) {
        _seenChampions.add(name);
      }
    }
    final regSim = RegExp(r'•\s*([^:\n\r]+):', caseSensitive: false);
    for (final m in regSim.allMatches(text)) {
      final name = m.group(1)?.trim();
      if (name != null && name.isNotEmpty && !_seenChampions.contains(name)) {
        final lower = name.toLowerCase();
        if (!lower.contains('hechizo') &&
            !lower.contains('runa') &&
            !lower.contains('plan') &&
            !lower.contains('spell') &&
            !lower.contains('build') &&
            !lower.contains('sort')) {
          _seenChampions.add(name);
        }
      }
    }
  }

  Future<void> _consultStrategy({bool isRefresh = false}) async {
    if (_isAnalyzing) return;

    if (widget.availableQueries <= 0) {
      widget.onNoQueries();
      return;
    }

    if (_enemyChampion == null || _enemyChampion!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          content: Text('Por favor selecciona el campeón rival de tu línea.'),
        ),
      );
      return;
    }

    if (_isOtpMode && (_myChampion == null || _myChampion!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          content: Text('Selecciona tu campeón para recibir la build y runas anti-matchup.'),
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _isRefreshing = isRefresh;
      _errorMessage = null;
    });

    HapticFeedback.mediumImpact();

    try {
      final lang = LanguageService.instance.currentLanguage;
      final bodyData = <String, dynamic>{
        'main_role': _selectedRole,
        'enemy_champion': _enemyChampion,
        'my_champion': _isOtpMode ? (_myChampion ?? '') : '',
        'game_mode': _gameMode,
        'language': lang,
      };

      if (isRefresh && _seenChampions.isNotEmpty) {
        bodyData['exclude_champions'] = _seenChampions.join(', ');
      }

      final res = await ApiClient.post(
        '/draft/manual',
        authenticated: true,
        body: bodyData,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          final rec = (data['recommendation'] as String?) ?? 'Sin recomendación clara.';
          _extractSeenChampions(rec);
          setState(() {
            _recommendationText = rec;
            _isAnalyzing = false;
            _isRefreshing = false;
          });
          widget.onDataChanged();
          HapticFeedback.lightImpact();
        }
      } else if (res.statusCode == 402) {
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
            _isRefreshing = false;
          });
          widget.onNoQueries();
        }
      } else {
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
            _isRefreshing = false;
            _errorMessage = 'Error del servidor (${res.statusCode}): ${res.body}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _isRefreshing = false;
          _errorMessage = 'Error de conexión: $e';
        });
      }
    }
  }

  void _showChampionPickerModal({required bool isMyChampion}) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChampionPickerSheet(
        title: isMyChampion ? 'Elige tu Campeón (Tu Pick)' : 'Elige el Rival de tu Línea',
        selectedChampion: isMyChampion ? _myChampion : _enemyChampion,
        onSelected: (champ) {
          setState(() {
            if (isMyChampion) {
              _myChampion = champ;
            } else {
              _enemyChampion = champ;
            }
            _recommendationText = null;
            _seenChampions.clear();
          });
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app_rounded, color: Color(0xFF00E5FF), size: 20),
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
              color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded, color: Color(0xFF00E5FF), size: 16),
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
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 20),
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
                color: const Color(0xFF94A3B8),
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
                          _recommendationText = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF00E5FF) : Colors.white10,
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
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
                              color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
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
                color: const Color(0xFF131B2E),
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
                          color: !_isOtpMode ? const Color(0xFF00E5FF).withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: !_isOtpMode ? Border.all(color: const Color(0xFF00E5FF)) : null,
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
                          color: _isOtpMode ? const Color(0xFFC89B3C).withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: _isOtpMode ? Border.all(color: const Color(0xFFC89B3C)) : null,
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
                      accentColor: const Color(0xFFC89B3C),
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
                    accentColor: const Color(0xFFEF4444),
                    icon: Icons.local_fire_department_rounded,
                    onTap: () => _showChampionPickerModal(isMyChampion: false),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            // Botón de Análisis Principal
            ElevatedButton(
              onPressed: _isAnalyzing ? null : () => _consultStrategy(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF090D16),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: const Color(0xFF00E5FF).withValues(alpha: 0.4),
              ),
              child: _isAnalyzing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF090D16),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _isRefreshing ? 'Buscando alternativas...' : 'Analizando estrategia táctica...',
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

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                ),
              ),
            ],

            // 4. Resultado del Análisis
            if (_recommendationText != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.35)),
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
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00E5FF), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'RECOMENDACIÓN TÁCTICA',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF00E5FF),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                          tooltip: 'Copiar texto',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _recommendationText!));
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
                      _recommendationText!,
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
                        onPressed: _isAnalyzing ? null : () => _consultStrategy(isRefresh: true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00E5FF),
                          side: const BorderSide(color: Color(0xFF00E5FF)),
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
          color: const Color(0xFF1E293B),
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

class _ChampionPickerSheet extends StatefulWidget {
  final String title;
  final String? selectedChampion;
  final ValueChanged<String> onSelected;

  const _ChampionPickerSheet({
    required this.title,
    required this.selectedChampion,
    required this.onSelected,
  });

  @override
  State<_ChampionPickerSheet> createState() => _ChampionPickerSheetState();
}

class _ChampionPickerSheetState extends State<_ChampionPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = AppConstants.wildRiftChampions;
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = AppConstants.wildRiftChampions;
      } else {
        _filtered = AppConstants.wildRiftChampions
            .where((c) => c.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar campeón (ej. Zed, Yasuo, Ahri)...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E5FF)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              itemCount: _filtered.length,
              itemBuilder: (ctx, idx) {
                final champ = _filtered[idx];
                final isSelected = champ == widget.selectedChampion;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  tileColor: isSelected ? const Color(0xFF00E5FF).withValues(alpha: 0.12) : null,
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF1E293B),
                    radius: 18,
                    child: Text(
                      champ.substring(0, 1),
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF090D16) : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    champ,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? const Color(0xFF00E5FF) : Colors.white,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5FF), size: 20)
                      : null,
                  onTap: () => widget.onSelected(champ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
