import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/services/api_client.dart';
import '../core/services/native_service.dart';
import '../core/services/session_service.dart';
import '../shared/widgets/hextech_orb.dart';
import '../theme/app_theme.dart';
import '../widgets/tutorial_dialog.dart';
import 'achievements_screen.dart';
import 'login_screen.dart';

class IndexScreen extends StatefulWidget {
  final String sessionToken;

  const IndexScreen({
    super.key,
    required this.sessionToken,
  });

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  StreamSubscription? _eventSubscription;
  late String _sessionToken;

  bool _isActive = false;
  int _availableQueries = 13;
  int _dailyQueries = 3;
  int _bonusQueries = 10;
  int _adQueries = 0;

  String _mainRole = 'Auto';
  String _secondaryRole = 'Auto';
  String _otpChampion = '';
  String _main1Champion = '';
  String _main2Champion = '';

  bool _isLoadingQueries = false;
  String? _userName;
  String? _userPhotoUrl;
  String? _referralCode;
  int _referralCount = 0;
  int _referralRewardsClaimed = 0;
  bool _hasRedeemedReferral = false;

  @override
  void initState() {
    super.initState();
    _sessionToken = widget.sessionToken;
    _loadCachedState();
    _fetchUserData();
    _listenToNativeEvents();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TutorialDialog.checkAndShow(context);
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _availableQueries = prefs.getInt('available_queries') ?? 13;
        _dailyQueries = prefs.getInt('daily_queries') ?? 3;
        _bonusQueries = prefs.getInt('bonus_queries') ?? 10;
        _adQueries = prefs.getInt('ad_queries') ?? 0;
        _mainRole = prefs.getString('pref_main_role') ?? 'Auto';
        _secondaryRole = prefs.getString('pref_secondary_role') ?? 'Auto';
        _otpChampion = prefs.getString('pref_otp_champion') ?? '';
        _main1Champion = prefs.getString('pref_main1_champion') ?? '';
        _main2Champion = prefs.getString('pref_main2_champion') ?? '';
      });
    }
  }

  void _listenToNativeEvents() {
    _eventSubscription = NativeService.onEvent.listen((event) {
      final code = event['code'];
      if (!mounted) return;

      if (code == 999) {
        // Servicio finalizado
        setState(() {
          _isActive = false;
        });
      } else if (code == 200) {
        // Análisis exitoso: descontar 1 consulta
        _decrementQuery();
      } else if (code == 402) {
        // Sin consultas disponibles
        setState(() {
          _isActive = false;
          _availableQueries = 0;
        });
        _showNoQueriesDialog();
      }
    });
  }

  Future<void> _decrementQuery() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_availableQueries > 0) {
        _availableQueries--;
      }
      if (_dailyQueries > 0) {
        _dailyQueries--;
      } else if (_bonusQueries > 0) {
        _bonusQueries--;
      } else if (_adQueries > 0) {
        _adQueries--;
      }
    });
    await prefs.setInt('available_queries', _availableQueries);
    await prefs.setInt('daily_queries', _dailyQueries);
    await prefs.setInt('bonus_queries', _bonusQueries);
    await prefs.setInt('ad_queries', _adQueries);
  }

  Future<void> _fetchUserData() async {
    try {
      final response = await ApiClient.get('/api/v1/auth/me', authenticated: true);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          final serverQueries = data['available_queries'];
          final prefs = await SharedPreferences.getInstance();
          final dailyGranted = data['daily_reward_granted'] == true;
          setState(() {
            _userName = data['username'] ?? 'Jugador';
            _userPhotoUrl = data['profile_pic'];
            _referralCode = data['referral_code'];
            _referralCount = (data['referral_count'] is int) ? data['referral_count'] : 0;
            _referralRewardsClaimed = (data['referral_rewards_claimed'] is int) ? data['referral_rewards_claimed'] : 0;
            _hasRedeemedReferral = data['has_redeemed_referral'] == true;
            if (serverQueries != null && serverQueries is int) {
              _availableQueries = serverQueries;
              prefs.setInt('available_queries', serverQueries);
            }
            if (data['daily_queries'] is int) {
              _dailyQueries = data['daily_queries'];
              prefs.setInt('daily_queries', _dailyQueries);
            }
            if (data['bonus_queries'] is int) {
              _bonusQueries = data['bonus_queries'];
              prefs.setInt('bonus_queries', _bonusQueries);
            }
            if (data['ad_queries'] is int) {
              _adQueries = data['ad_queries'];
              prefs.setInt('ad_queries', _adQueries);
            }
          });

          if (dailyGranted && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF00E5FF),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                content: const Row(
                  children: [
                    Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 26),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '🎁 ¡Bono Diario Activo! Tus 3 consultas diarias están listas para hoy.',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else if (response.statusCode == 401) {
        if (mounted) {
          _handleLogout();
        }
      }
    } catch (e) {
      debugPrint('Error al obtener datos de usuario: $e');
    }
  }

  void _openAchievementsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AchievementsScreen(
          referralCode: _referralCode ?? '',
          referralCount: _referralCount,
          referralRewardsClaimed: _referralRewardsClaimed,
          hasRedeemedReferral: _hasRedeemedReferral,
          onDataChanged: _fetchUserData,
        ),
      ),
    );
  }

  void _showRolesAndOtpDialog() {
    final otpController = TextEditingController(text: _otpChampion);
    final main1Controller = TextEditingController(text: _main1Champion);
    final main2Controller = TextEditingController(text: _main2Champion);
    String tempMainRole = _mainRole;
    String tempSecondaryRole = _secondaryRole;

    final roles = ['Auto', 'Barón (Top)', 'Jungla', 'Mid', 'Tirador (ADC)', 'Soporte'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      children: [
                        const Icon(Icons.tune_rounded, color: Color(0xFFC89B3C), size: 24),
                        const SizedBox(width: 10),
                        Text(
                          'Mis Roles y Campeones',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'La IA priorizará recomendaciones adaptadas a tus líneas y campeones favoritos.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                    ),
                    const SizedBox(height: 18),

                    // Línea Principal
                    Text(
                      'Línea Principal (Rol 1)',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00E5FF),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: roles.map((role) {
                        final isSelected = tempMainRole == role;
                        return ChoiceChip(
                          label: Text(role),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) setModalState(() => tempMainRole = role);
                          },
                          selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          labelStyle: TextStyle(
                            color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF00E5FF) : Colors.white12,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Línea Secundaria
                    Text(
                      'Línea Secundaria (Rol 2)',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFC89B3C),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: roles.map((role) {
                        final isSelected = tempSecondaryRole == role;
                        return ChoiceChip(
                          label: Text(role),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) setModalState(() => tempSecondaryRole = role);
                          },
                          selectedColor: const Color(0xFFC89B3C).withValues(alpha: 0.25),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          labelStyle: TextStyle(
                            color: isSelected ? const Color(0xFFC89B3C) : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFFC89B3C) : Colors.white12,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // Campeón OTP
                    Text(
                      'Campeón OTP (Tu Especialidad)',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: otpController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ej: Yasuo, Zed, Kai\'Sa, Thresh...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFC89B3C)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Mains Secundarios
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Main 1 (Opcional)',
                                style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: main1Controller,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Ej: Lee Sin',
                                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.white12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.white12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Main 2 (Opcional)',
                                style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: main2Controller,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Ej: Nautilus',
                                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.white12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.white12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Botón Guardar
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          setState(() {
                            _mainRole = tempMainRole;
                            _secondaryRole = tempSecondaryRole;
                            _otpChampion = otpController.text.trim();
                            _main1Champion = main1Controller.text.trim();
                            _main2Champion = main2Controller.text.trim();
                          });
                          await prefs.setString('pref_main_role', _mainRole);
                          await prefs.setString('pref_secondary_role', _secondaryRole);
                          await prefs.setString('pref_otp_champion', _otpChampion);
                          await prefs.setString('pref_main1_champion', _main1Champion);
                          await prefs.setString('pref_main2_champion', _main2Champion);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Preferencias guardadas correctamente'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC89B3C),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          'Guardar Preferencias',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showQueriesBreakdownDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFF00E5FF), size: 26),
                  const SizedBox(width: 10),
                  Text(
                    '$_availableQueries Consultas Disponibles',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Cada captura de pantalla en draft consume 1 consulta. Tu saldo se compone de:',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
              const SizedBox(height: 16),

              // Item 1: Consultas Diarias
              _buildQueryItem(
                icon: Icons.calendar_today_rounded,
                iconColor: const Color(0xFF00E5FF),
                title: 'Consultas Diarias',
                value: '$_dailyQueries / 3 máx',
                description: 'Se renuevan cada día (tope de 3 acumuladas).',
              ),
              const SizedBox(height: 12),

              // Item 2: Bono de Bienvenida
              _buildQueryItem(
                icon: Icons.card_giftcard_rounded,
                iconColor: const Color(0xFFC89B3C),
                title: 'Bono de Bienvenida',
                value: '$_bonusQueries / 10 máx',
                description: 'Consultas iniciales para explorar la app.',
              ),
              const SizedBox(height: 12),

              // Item 3: Consultas por Recarga
              _buildQueryItem(
                icon: Icons.all_inclusive_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Consultas por Recarga',
                value: '$_adQueries acumuladas',
                description: 'Por ver anuncios o invitar amigos. ¡Crecen sin límite!',
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _obtainQueries();
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Obtener +5 Consultas Gratis'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQueryItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                      ),
                    ),
                  ],
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar sesión', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '¿Deseas cerrar la sesión de ${_userName ?? "tu cuenta"}?',
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(ctx).pop();
              _handleLogout();
            },
            child: const Text('Salir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // OBTENER CONSULTAS (MÉTODO PRINCIPAL RECOMPENSADO)
  // ==============================================================
  Future<void> _obtainQueries() async {
    if (_isLoadingQueries) return;

    setState(() {
      _isLoadingQueries = true;
    });

    HapticFeedback.mediumImpact();

    // ==========================================================
    // NOTA PARA FASE 2 (VINCULACIÓN CON APPODEAL):
    // Una vez que la app esté en producción en Google Play Store:
    // Aquí invocaremos el anuncio de video recompensado:
    //
    // try {
    //   if (await Appodeal.isLoaded(AppodealAdType.RewardedVideo)) {
    //     await Appodeal.show(AppodealAdType.RewardedVideo);
    //     // En el callback onRewardedVideoFinished:
    //   }
    // } catch (e) { ... }
    // ==========================================================

    try {
      // Intentar actualizar en el backend
      final response = await ApiClient.post('/api/v1/user/obtain-queries');
      int added = 5;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['available_queries'] is int) {
          _availableQueries = data['available_queries'];
        } else {
          _availableQueries += added;
        }
        if (data['ad_queries'] is int) {
          _adQueries = data['ad_queries'];
        } else {
          _adQueries += added;
        }
        if (data['daily_queries'] is int) {
          _dailyQueries = data['daily_queries'];
        }
        if (data['bonus_queries'] is int) {
          _bonusQueries = data['bonus_queries'];
        }
      } else {
        // Modo offline / respaldo local
        _availableQueries += added;
        _adQueries += added;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('available_queries', _availableQueries);
      await prefs.setInt('ad_queries', _adQueries);
      await prefs.setInt('daily_queries', _dailyQueries);
      await prefs.setInt('bonus_queries', _bonusQueries);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '¡+$added consultas añadidas! Tienes $_availableQueries consultas disponibles.',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Si falla la red, otorgamos igualmente para no bloquear al usuario
      _availableQueries += 5;
      _adQueries += 5;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('available_queries', _availableQueries);
      await prefs.setInt('ad_queries', _adQueries);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Text('¡+5 consultas añadidas! Tienes $_availableQueries consultas.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingQueries = false;
        });
      }
    }
  }

  void _showNoQueriesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 28),
            SizedBox(width: 8),
            Text('Sin Consultas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Has consumido todas tus consultas disponibles.\n\nPresiona "Obtener consultas" para recargar gratis inmediatamente.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _obtainQueries();
            },
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Obtener consultas'),
          ),
        ],
      ),
    );
  }

  Future<bool> _checkAndShowDisclosure() async {
    final prefs = await SharedPreferences.getInstance();
    final hasAccepted = prefs.getBool('hasAcceptedDisclosure') ?? false;

    if (hasAccepted) {
      return true;
    }

    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Permiso de Captura de Pantalla',
            style: TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Drafting requiere capturar la pantalla para analizar la partida de tu juego.\n\n'
            'La captura se procesa para generar recomendaciones con Inteligencia Artificial.\n'
            'No almacenamos tus imágenes permanentemente ni compartimos datos con terceros.\n\n'
            '¿Deseas activar el asistente flotante?',
            style: TextStyle(color: AppTheme.textMuted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Rechazar', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Acepto', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await prefs.setBool('hasAcceptedDisclosure', true);
      return true;
    }
    return false;
  }

  Future<void> _toggleService() async {
    if (_isActive) {
      await NativeService.stopCaptureService();
      if (!mounted) return;
      setState(() {
        _isActive = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Asistente desactivado'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      if (_availableQueries <= 0) {
        _showNoQueriesDialog();
        return;
      }

      final hasPermission = await _checkAndShowDisclosure();
      if (!hasPermission) return;

      final otpCombined = [
        _otpChampion,
        _main1Champion,
        _main2Champion,
      ].where((s) => s.trim().isNotEmpty).join(', ');

      bool started = await NativeService.startCaptureService(
        baseUrl: AppConfig.apiBaseUrl,
        sessionToken: _sessionToken,
        mainRole: _mainRole,
        secondaryRole: _secondaryRole,
        autofillRole: "Auto",
        isPremium: true,
        planTier: "plus",
        otpChampions: otpCombined,
        activeCreatorId: "",
      );

      if (started) {
        if (!mounted) return;
        setState(() {
          _isActive = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text(
              '¡Asistente activo! Abre tu juego y toca la burbuja flotante.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    await NativeService.stopCaptureService();
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {}
    await GoogleSignIn.instance.signOut();
    await SessionService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF080B11),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // --- 1. TOP HEADER BAR (Compacto, SIN DESBORDAMIENTO) ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Brand Logo & Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF0052D4)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Drafting',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),

                    // Actions: Tutorial & User Profile Avatar (Compact)
                    Row(
                      children: [
                        // Tutorial / Help Button
                        Container(
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                          ),
                          child: IconButton(
                            tooltip: 'Ver tutorial',
                            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF00E5FF), size: 20),
                            padding: const EdgeInsets.all(7),
                            constraints: const BoxConstraints(),
                            onPressed: () => TutorialDialog.show(context),
                          ),
                        ),

                        // User Profile Avatar (Tap to logout / info)
                        InkWell(
                          onTap: _showLogoutDialog,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                            ),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                              backgroundImage: _userPhotoUrl != null ? NetworkImage(_userPhotoUrl!) : null,
                              child: _userPhotoUrl == null
                                  ? const Icon(Icons.person, color: Colors.white, size: 18)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // --- 2. CONSULTAS & RECARGA CARD (Compacto y unificado) ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1E293B).withValues(alpha: 0.75),
                        const Color(0xFF0F172A).withValues(alpha: 0.9),
                      ],
                    ),
                    border: Border.all(
                      color: _availableQueries > 0
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
                          : Colors.redAccent.withValues(alpha: 0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_availableQueries > 0 ? const Color(0xFF00E5FF) : Colors.redAccent).withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          color: _availableQueries > 0 ? const Color(0xFF00E5FF) : Colors.redAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _showQueriesBreakdownDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '$_availableQueries ${_availableQueries == 1 ? "Consulta" : "Consultas"}',
                                    style: GoogleFonts.outfit(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.info_outline_rounded, size: 14, color: Colors.white38),
                                ],
                              ),
                              Text(
                                'Toca para ver desglose',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Botón Recarga Rápida
                      ElevatedButton(
                        onPressed: _isLoadingQueries ? null : _obtainQueries,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoadingQueries
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_rounded, size: 18),
                                  SizedBox(width: 4),
                                  Text('+5 Gratis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // --- 3. PROTAGONISTA CENTRAL: ESFERA HEXTECH (ACTIVAR ASISTENTE) ---
              Center(
                child: HextechOrb(
                  isActive: _isActive,
                  onTap: _toggleService,
                ),
              ),

              const SizedBox(height: 24),

              // Status indicator below Orb
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isActive
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isActive
                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isActive ? const Color(0xFF10B981) : Colors.white54,
                        boxShadow: _isActive
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.8),
                                  blurRadius: 8,
                                )
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isActive
                          ? 'ASISTENTE ACTIVO SOBRE WILD RIFT'
                          : 'TOCA LA ESFERA PARA ACTIVAR',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: _isActive ? const Color(0xFF10B981) : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // --- 4. ACCESO A CONFIGURACIÓN DE ROLES Y CAMPEONES ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: InkWell(
                  onTap: _showRolesAndOtpDialog,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          ),
                          child: const Icon(Icons.tune_rounded, color: Color(0xFF00E5FF), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Mis Roles y Campeones OTP',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '$_mainRole / $_secondaryRole${_otpChampion.isNotEmpty ? " • OTP: $_otpChampion" : ""}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 12),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // --- 5. ACCESO A LA PANTALLA EXCLUSIVA DE LOGROS Y RECOMPENSAS ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: InkWell(
                  onTap: _openAchievementsScreen,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          ),
                          child: const Icon(Icons.emoji_events_rounded, color: Color(0xFF10B981), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Logros y Recompensas',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Invita a 2 amigos y gana +5 consultas',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$_referralRewardsClaimed/5',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 12),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Bottom footer hint
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(
                  'Abre tu juego después de activar. La burbuja flotará en pantalla.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
