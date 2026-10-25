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
import '../widgets/referral_dialog.dart';
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

class _IndexScreenState extends State<IndexScreen> with SingleTickerProviderStateMixin {
  StreamSubscription? _eventSubscription;
  late String _sessionToken;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  bool _isActive = false;
  int _availableQueries = 10;
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
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 6.0, end: 24.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

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
    _glowController.dispose();
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _availableQueries = prefs.getInt('available_queries') ?? 10;
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
    });
    await prefs.setInt('available_queries', _availableQueries);
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
                        '🎁 ¡Bono Diario Reclamado! +3 consultas gratis para hoy.',
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

  void _showReferralDialog() {
    ReferralDialog.show(
      context: context,
      referralCode: _referralCode ?? '',
      referralCount: _referralCount,
      referralRewardsClaimed: _referralRewardsClaimed,
      hasRedeemedReferral: _hasRedeemedReferral,
      onDataChanged: _fetchUserData,
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
      } else {
        // Modo offline / respaldo local
        _availableQueries += added;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('available_queries', _availableQueries);

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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('available_queries', _availableQueries);

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

      bool started = await NativeService.startCaptureService(
        baseUrl: AppConfig.apiBaseUrl,
        sessionToken: _sessionToken,
        mainRole: "Auto",
        secondaryRole: "Auto",
        autofillRole: "Auto",
        isPremium: true,
        planTier: "plus",
        otpChampions: "",
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
              // --- 1. TOP HEADER BAR ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
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

                    Row(
                      children: [
                        // Referral / Invite Friends Button
                        Container(
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                          ),
                          child: IconButton(
                            tooltip: 'Invitar amigos (+5)',
                            icon: const Icon(Icons.people_alt_rounded, color: Color(0xFF10B981), size: 20),
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(),
                            onPressed: _showReferralDialog,
                          ),
                        ),

                        // Tutorial / Help Button
                        Container(
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                          ),
                          child: IconButton(
                            tooltip: 'Ver tutorial',
                            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF00E5FF), size: 20),
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(),
                            onPressed: () => TutorialDialog.show(context),
                          ),
                        ),

                        // User Profile Chip / Logout
                        InkWell(
                          onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppTheme.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
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
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                              backgroundImage: _userPhotoUrl != null ? NetworkImage(_userPhotoUrl!) : null,
                              child: _userPhotoUrl == null
                                  ? const Icon(Icons.person, color: Colors.white, size: 16)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 100),
                              child: Text(
                                _userName ?? 'Jugador',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.logout, color: Colors.white54, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

              const SizedBox(height: 12),

              // --- 2. CONSULTAS DISPONIBLES CARD ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1E293B).withValues(alpha: 0.8),
                        const Color(0xFF0F172A).withValues(alpha: 0.9),
                      ],
                    ),
                    border: Border.all(
                      color: _availableQueries > 0
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
                          : Colors.redAccent.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_availableQueries > 0 ? const Color(0xFF00E5FF) : Colors.redAccent)
                              .withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          color: _availableQueries > 0 ? const Color(0xFF00E5FF) : Colors.redAccent,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_availableQueries ${_availableQueries == 1 ? "Consulta" : "Consultas"} disponibles',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Cada captura de pantalla consume 1 consulta',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // --- 2.5 BANNER RECOMENDADO: INVITA A 2 AMIGOS Y GANA +5 ---
              Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 12.0),
                child: InkWell(
                  onTap: _showReferralDialog,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.card_giftcard_rounded, color: Color(0xFF10B981), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Invita a 2 amigos y gana +5 consultas',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF10B981),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$_referralRewardsClaimed/5',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 12),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // --- 3. BOTÓN DESTACADO: "OBTENER CONSULTAS" ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: AnimatedBuilder(
                    animation: _glowAnimation,
                    builder: (context, child) {
                      final isZero = _availableQueries <= 0;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF10B981), // Emerald
                              Color(0xFF059669),
                            ],
                          ),
                          border: isZero
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  width: 1.5,
                                )
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: isZero ? 0.75 : 0.4),
                              blurRadius: isZero ? _glowAnimation.value : 18,
                              spreadRadius: isZero ? (_glowAnimation.value / 4.5) : 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: ElevatedButton(
                      onPressed: _isLoadingQueries ? null : _obtainQueries,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _isLoadingQueries
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 24),
                                const SizedBox(width: 10),
                                Text(
                                  'Obtener consultas',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    '+5',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // --- 4. CENTRAL ACTION: HEXTECH ORB (CAPTURA DE PANTALLA) ---
              Center(
                child: HextechOrb(
                  isActive: _isActive,
                  onTap: _toggleService,
                ),
              ),

              const SizedBox(height: 28),

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
                          ? 'ASISTENTE ACTIVO SOBRE TU JUEGO'
                          : 'TOCA LA ESFERA PARA ACTIVAR EL ASISTENTE',
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

              const Spacer(),

              // Bottom footer hint
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'Abre tu juego después de activar. La burbuja flotará en pantalla.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.4),
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
