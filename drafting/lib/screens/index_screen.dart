import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/models/user_profile.dart';
import '../core/services/ad_service.dart';
import '../core/services/api_client.dart';
import '../core/services/language_service.dart';
import '../core/services/native_service.dart';
import '../core/services/session_service.dart';
import '../core/services/update_service.dart';
import '../shared/widgets/champion_picker_sheet.dart';
import '../shared/widgets/hextech_orb.dart';
import '../shared/widgets/home_modals.dart';
import '../theme/app_theme.dart';
import '../widgets/tutorial_dialog.dart';
import 'achievements_screen.dart';
import 'dodge_simulator_screen.dart';
import 'donations_screen.dart';
import 'events_screen.dart';
import 'login_screen.dart';
import 'lol_pc_scanner_screen.dart';
import 'manual_draft_screen.dart';
import 'reels_screen.dart';
import 'store_screen.dart';
import 'trivia_screen.dart';

class IndexScreen extends StatefulWidget {
  final String sessionToken;

  const IndexScreen({
    super.key,
    required this.sessionToken,
  });

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription? _eventSubscription;
  late String _sessionToken;

  bool _isActive = false;
  final UserProfile _user = UserProfile();
  String _selectedGameMode = 'wild_rift'; // 'wild_rift' o 'lol_pc'
  String _selectedModelTier = 'local'; // Motor unificado: IA Local Híbrida + Voz Local
  String _selectedMainRole = 'Mid';
  String _selectedOtpChampion = '';

  bool _isLoadingQueries = false;
  bool _localModelDownloaded = false;
  bool _localModelDownloading = false;
  int _localModelProgress = 0;
  double _localModelSizeMb = 0.0;

  final GlobalKey<EventsScreenState> _eventsKey = GlobalKey<EventsScreenState>();
  Map<String, dynamic>? _liveEvent;

  /// Control de visibilidad de la pestaña de Donaciones (oculto temporalmente para lanzamiento)
  static const bool showDonationsTab = false;

  int _currentTab = 1; // 0: Reels, 1: Home, 2: Game 2D

  /// Sistema de Lazy Load y Priorización estilo SO:
  /// - Solo se montan en RAM las pestañas que el usuario realmente ha visitado.
  /// - Cuando el simulador 2D de alta prioridad está activo, todas las pantallas en segundo plano
  ///   congelan sus Tickers/Animaciones (0% uso de CPU/GPU en background).
  final Set<int> _visitedTabs = {1};
  bool _isHighPriorityGameRunning = false;

  bool get _isLocalModelSelected => _selectedModelTier == 'local';

  int get _availableQueries =>
      _isLocalModelSelected ? 9999 : _user.queries.queriesForModel(_selectedModelTier);

  bool get _isSelectedModelAdOnCooldown =>
      _isLocalModelSelected ? false : _user.queries.isAdOnCooldown(_selectedModelTier);

  String get _selectedModelDisplayName {
    switch (_selectedModelTier) {
      case 'local':
        return 'Local ∞';
      case 'flake':
        return 'Flake 1.0';
      case 'aureon':
        return 'Aureon 1.0';
      default:
        return 'Classic';
    }
  }

  Future<void> _selectModelTier(String tier) async {
    if (_selectedModelTier == tier) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedModelTier = tier);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('model_tier', tier);
    await NativeService.setNativeModelTier(tier);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionToken = widget.sessionToken;
    _loadCachedState();
    _fetchUserData();
    _listenToNativeEvents();
    _refreshLocalModelStatus();
    AdService.loadRewardedAd();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TutorialDialog.checkAndShow(context);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      UpdateService.instance.checkAndPromptIfNeeded(
        context,
        langCode: LanguageService.instance.currentLanguage,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _user.loadFromPrefs(prefs);
        _selectedMainRole = prefs.getString('selected_main_role') ?? 'Mid';
        _selectedOtpChampion = prefs.getString('selected_otp_champion') ?? '';
        _selectedGameMode = prefs.getString('game_mode') ?? 'wild_rift';
        _selectedModelTier = 'local';
      });
    }
  }

  Future<void> _updateOtpChampion(String champ) async {
    HapticFeedback.selectionClick();
    setState(() => _selectedOtpChampion = champ);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_otp_champion', champ);
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
        // Análisis exitoso: descontar 1 consulta y sincronizar con servidor
        _decrementQuery();
      } else if (code == 401) {
        // Sesión expirada o iniciada en otro dispositivo
        NativeService.stopCaptureService();
        setState(() {
          _isActive = false;
        });
        _handleLogout();
      } else if (code == 402) {
        // Sin consultas disponibles: detener inmediatamente el servicio nativo
        NativeService.stopCaptureService();
        setState(() {
          _isActive = false;
          _user.queries.available = 0;
        });
        _showNoQueriesDialog();
      } else if (code == 204 || code == 205) {
        // Eventos de Google Play In-App Update en segundo plano (descargando / descargado)
        UpdateService.instance.handleNativeUpdateEvent(
          event,
          context,
          langCode: LanguageService.instance.currentLanguage,
        );
      } else if (code == 210) {
        final pct = (event['progress'] as num?)?.toInt() ?? 0;
        setState(() {
          _localModelDownloading = true;
          _localModelProgress = pct;
        });
      } else if (code == 211) {
        setState(() {
          _localModelDownloading = false;
          _localModelDownloaded = true;
          _localModelProgress = 100;
        });
        _refreshLocalModelStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('IA Local descargada y verificada (SHA-256 OK).'),
            backgroundColor: AppTheme.hextechEmerald,
          ),
        );
      } else if (code == 212) {
        final msg = event['message']?.toString() ?? 'Error descargando modelo local.';
        setState(() {
          _localModelDownloading = false;
          _localModelProgress = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
        );
      }
    });
  }

  Future<void> _refreshLocalModelStatus() async {
    final status = await NativeService.getLocalModelStatus();
    if (!mounted) return;
    setState(() {
      _localModelDownloaded = status['isDownloaded'] == true;
      _localModelDownloading = status['isDownloading'] == true;
      _localModelSizeMb = (status['sizeMb'] as num?)?.toDouble() ?? 0.0;
    });
  }

  Future<void> _handleLocalModelTap() async {
    HapticFeedback.selectionClick();
    if (_localModelDownloading) return;
    if (_localModelDownloaded) {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('IA Local lista', style: TextStyle(color: Colors.white)),
          content: Text(
            'El modelo GGUF (${_localModelSizeMb.toStringAsFixed(1)} MB) está activo en tu dispositivo.\n\n¿Deseas eliminarlo para liberar espacio?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Mantener'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (shouldDelete == true) {
        await NativeService.deleteLocalModel();
        await _refreshLocalModelStatus();
      }
    } else {
      setState(() {
        _localModelDownloading = true;
        _localModelProgress = 0;
      });
      await NativeService.downloadLocalModel();
    }
  }

  Future<void> _decrementQuery() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _user.queries.decrementForModel(_selectedModelTier);
    });
    await _user.queries.saveToPrefs(prefs);

    // Sincronizar en segundo plano con el backend
    _fetchUserData();

    // Si se agotaron las consultas, detener asistente y avisar al usuario
    if (_availableQueries == 0 && mounted) {
      NativeService.stopCaptureService();
      setState(() {
        _isActive = false;
      });
      _showNoQueriesDialog();
    }
  }

  Future<void> _fetchUserData() async {
    try {
      final response = await ApiClient.get('/api/v1/auth/me', authenticated: true);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          final dailyGranted = data['daily_reward_granted'] == true;
          await _user.updateFromMeResponse(data, prefs);
          if (mounted) {
            setState(() {});
          }

          if (data['app_version'] is Map<String, dynamic> && mounted) {
            UpdateService.instance.checkAndPromptIfNeeded(
              context,
              serverVersionPayload: data['app_version'] as Map<String, dynamic>,
              langCode: LanguageService.instance.currentLanguage,
            );
          }

          if (dailyGranted && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.hextechCyan,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                content: Row(
                  children: [
                    const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        LanguageService.instance.tr('home_daily_bonus_snack'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
      } else {
        if (mounted) {
          UpdateService.instance.checkAndPromptIfNeeded(
            context,
            langCode: LanguageService.instance.currentLanguage,
          );
        }
      }
    } catch (e) {
      debugPrint('Error al obtener datos de usuario: $e');
      if (mounted) {
        UpdateService.instance.checkAndPromptIfNeeded(
          context,
          langCode: LanguageService.instance.currentLanguage,
        );
      }
    }
  }

  void _openStoreScreen() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoreScreen(
          onDataChanged: _fetchUserData,
          isTab: false,
        ),
      ),
    );
  }

  void _openEventsScreen() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventsScreen(
          key: _eventsKey,
          isTab: false,
          userEmail: _user.userEmail,
          onLiveEventChanged: (live) {
            if (mounted) {
              setState(() => _liveEvent = live);
            }
          },
        ),
      ),
    );
  }

  void _openAchievementsScreen() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AchievementsScreen(
          referralCode: _user.referralCode ?? '',
          referralCount: _user.referralCount,
          referralRewardsClaimed: _user.referralRewardsClaimed,
          hasRedeemedReferral: _user.hasRedeemedReferral,
          onDataChanged: _fetchUserData,
          isTab: false,
        ),
      ),
    );
  }

  void _openTriviaScreen() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TriviaScreen(
          onLivesChanged: _fetchUserData,
          isTab: false,
        ),
      ),
    );
  }

  void _showQueriesBreakdownDialog() {
    HomeModals.showQueriesBreakdown(
      context: context,
      user: _user,
      onObtainFreeQueries: _obtainQueries,
      onOpenStore: _openStoreScreen,
    );
  }

  void _showLogoutDialog() {
    HomeModals.showLogoutDialog(
      context: context,
      userName: _user.userName,
      onConfirmLogout: _handleLogout,
    );
  }

  void _showSettingsModal() {
    HapticFeedback.selectionClick();
    final lang = LanguageService.instance;
    final langOpt = lang.currentOption;
    final userPhotoUrl = _user.userPhotoUrl;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: AppTheme.hextechCyan.withValues(alpha: 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sheet handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.hextechCyan.withValues(alpha: 0.15),
                          ),
                          child: const Icon(Icons.settings_suggest_rounded, color: AppTheme.hextechCyan, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Ajustes del Sistema',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Opción 1: Cambiar Idioma
                InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    lang.showLanguagePickerModal(context);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardDark.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.hextechCyan.withValues(alpha: 0.12),
                          ),
                          child: const Icon(Icons.translate_rounded, color: AppTheme.hextechCyan, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Idioma / Language',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Cambiar el idioma de la aplicación',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.hextechCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.hextechCyan.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(langOpt.flag, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 5),
                              Text(
                                langOpt.badge,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Opción 2: Más Información (Tutorial / Guía)
                InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    TutorialDialog.show(context);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardDark.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.hextechGold.withValues(alpha: 0.12),
                          ),
                          child: const Icon(Icons.help_outline_rounded, color: AppTheme.hextechGold, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Más Información / Guía',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Aprende a usar el asistente y sus funciones',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Un poco más arriba del perfil: Mensaje 100% Seguro Riot Games
                InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    HomeModals.showSecurityInfoDialog(context);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.hextechEmerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.hextechEmerald.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_rounded, color: AppTheme.hextechEmerald, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '100% Seguro • Cumple políticas de Riot Games',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6EE7B7),
                            ),
                          ),
                        ),
                        const Icon(Icons.info_outline_rounded, color: Color(0xFF6EE7B7), size: 15),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // En la parte inferior: (Foto) (Correo) (Log out)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      // (Foto)
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                        backgroundImage: userPhotoUrl != null ? NetworkImage(userPhotoUrl) : null,
                        child: userPhotoUrl == null
                            ? const Icon(Icons.person, color: Colors.white, size: 22)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      // (Correo)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_user.userName != null && _user.userName!.isNotEmpty)
                              Text(
                                _user.userName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            Text(
                              _user.userEmail ?? 'invocador@riot.com',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // (Log out)
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showLogoutDialog();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.hextechCrimson.withValues(alpha: 0.15),
                          foregroundColor: AppTheme.hextechCrimson,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          side: BorderSide(color: AppTheme.hextechCrimson.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 16),
                        label: Text(
                          'Salir',
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
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

  Widget _buildDrawer() {
    final userPhotoUrl = _user.userPhotoUrl;

    return Drawer(
      backgroundColor: AppTheme.deepDarkBg,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.deepDarkBg,
          border: Border(
            right: BorderSide(
              color: AppTheme.hextechCyan.withValues(alpha: 0.25),
              width: 1.2,
            ),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header del Drawer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
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
                              colors: [AppTheme.hextechCyan, AppTheme.hextechBlue],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.hextechCyan.withValues(alpha: 0.35),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Drafting',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),

              // Opciones del Menú (Eventos, Logros, Trivia, Tienda, Ajustes)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  children: [
                    // 1. Eventos
                    _buildDrawerItem(
                      icon: Icons.podcasts_rounded,
                      iconColor: AppTheme.hextechCrimson,
                      title: 'Eventos & En Vivo',
                      subtitle: 'Torneos y directos de la comunidad',
                      badge: _liveEvent != null ? 'EN VIVO' : null,
                      badgeColor: AppTheme.hextechCrimson,
                      onTap: () {
                        Navigator.of(context).pop();
                        _openEventsScreen();
                      },
                    ),
                    const SizedBox(height: 6),

                    // 2. Logros
                    _buildDrawerItem(
                      icon: Icons.emoji_events_rounded,
                      iconColor: AppTheme.hextechEmerald,
                      title: 'Logros & Referidos',
                      subtitle: 'Recompensas y metas alcanzadas',
                      onTap: () {
                        Navigator.of(context).pop();
                        _openAchievementsScreen();
                      },
                    ),
                    const SizedBox(height: 6),

                    // 3. Trivia
                    _buildDrawerItem(
                      icon: Icons.quiz_rounded,
                      iconColor: const Color(0xFFA855F7),
                      title: 'Trivia Invocador',
                      subtitle: 'Demuestra cuánto sabes de LoL',
                      onTap: () {
                        Navigator.of(context).pop();
                        _openTriviaScreen();
                      },
                    ),
                    const SizedBox(height: 6),

                    // 4. Tienda
                    _buildDrawerItem(
                      icon: Icons.storefront_rounded,
                      iconColor: AppTheme.hextechGold,
                      title: 'Tienda de Consultas',
                      subtitle: 'Packs, ofertas y recarga rápida',
                      onTap: () {
                        Navigator.of(context).pop();
                        _openStoreScreen();
                      },
                    ),
                    const SizedBox(height: 12),

                    Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                    const SizedBox(height: 12),

                    // 5. Ajustes
                    _buildDrawerItem(
                      icon: Icons.settings_suggest_rounded,
                      iconColor: AppTheme.hextechCyan,
                      title: 'Ajustes',
                      subtitle: 'Idioma, guía y preferencias',
                      onTap: () {
                        Navigator.of(context).pop();
                        _showSettingsModal();
                      },
                    ),
                  ],
                ),
              ),

              // Footer del Menú Lateral
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Un poco más arriba: 100% seguro Riot Games
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        HomeModals.showSecurityInfoDialog(context);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.hextechEmerald.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.hextechEmerald.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.verified_user_rounded, color: AppTheme.hextechEmerald, size: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '100% Seguro • Cumple políticas Riot',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF6EE7B7),
                                ),
                              ),
                            ),
                            const Icon(Icons.info_outline_rounded, color: Color(0xFF6EE7B7), size: 13),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Parte inferior: (Foto) (Correo) (Log out)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.cardDark.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          // Foto de perfil
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                            backgroundImage: userPhotoUrl != null ? NetworkImage(userPhotoUrl) : null,
                            child: userPhotoUrl == null
                                ? const Icon(Icons.person, color: Colors.white, size: 18)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          // Correo
                          Expanded(
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_user.userName != null && _user.userName!.isNotEmpty)
                                Text(
                                  _user.userName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              Text(
                                _user.userEmail ?? 'invocador@riot.com',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Log out
                        IconButton(
                          tooltip: 'Cerrar Sesión',
                          icon: const Icon(Icons.logout_rounded, color: AppTheme.hextechCrimson, size: 20),
                          onPressed: () {
                            Navigator.of(context).pop();
                            _showLogoutDialog();
                          },
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
    ),
  );
}

  Widget _buildDrawerItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.cardDark.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor ?? AppTheme.hextechCrimson,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: GoogleFonts.outfit(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 18),
          ],
        ),
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

    if (_isSelectedModelAdOnCooldown) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.hextechCrimson,
            behavior: SnackBarBehavior.floating,
            content: Text('$_selectedModelDisplayName está en enfriamiento. Vuelve mañana.'),
          ),
        );
      }
      return;
    }

    HapticFeedback.mediumImpact();

    final String targetTier = _selectedModelTier;
    AdService.showRewardedAd(
      onUserEarnedReward: () async {
        try {
          final response = await ApiClient.post(
            '/api/v1/user/obtain-queries',
            authenticated: true,
            body: {'model_tier': targetTier},
          );
          int added = targetTier == 'classic' ? 2 : 1;

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            if (data['added'] is int) added = data['added'] as int;
            _user.queries.updateFromServerMap(data, fallbackAddedAdQueries: added);
          } else if (response.statusCode == 429) {
            String errMsg = LanguageService.instance.tr('home_wait_15s');
            try {
              final data = jsonDecode(response.body) as Map<String, dynamic>;
              _user.queries.updateFromServerMap(data);
              if (data['message'] != null) errMsg = data['message'].toString();
            } catch (_) {}
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.hextechCrimson,
                  behavior: SnackBarBehavior.floating,
                  content: Text(errMsg),
                ),
              );
            }
            return;
          }

          final prefs = await SharedPreferences.getInstance();
          await _user.queries.saveToPrefs(prefs);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.hextechEmerald,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                content: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        LanguageService.instance.tr(
                          'home_queries_added_snack',
                          {'added': '$added', 'total': '$_availableQueries'},
                        ),
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
          debugPrint('Error al registrar recompensa: $e');
        } finally {
          if (mounted) {
            setState(() {
              _isLoadingQueries = false;
            });
          }
        }
      },
      onAdFailed: (error) {
        if (mounted) {
          setState(() {
            _isLoadingQueries = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF334155),
              behavior: SnackBarBehavior.floating,
              content: Text(error),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
    );
  }

  void _showNoQueriesDialog() {
    HomeModals.showNoQueriesDialog(
      context: context,
      onObtainQueries: _obtainQueries,
    );
  }

  Future<void> _openLolPcScanner() async {
    if (_availableQueries <= 0) {
      _showNoQueriesDialog();
      return;
    }
    HapticFeedback.selectionClick();

    // Flujo en 2 pasos: abre directamente la cámara para capturar la pantalla del monitor
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

      if (photo == null) return; // Cancelado por el usuario

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LolPcScannerScreen(
            initialImage: File(photo.path),
            availableQueries: _availableQueries,
            onDataChanged: _fetchUserData,
            onNoQueries: _showNoQueriesDialog,
            mainRole: _selectedMainRole,
          ),
        ),
      );
      _fetchUserData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.instance.tr('pc_scanner_camera_error', {'error': '$e'})),
          backgroundColor: AppTheme.hextechCrimson,
        ),
      );
    }
  }

  Future<void> _toggleService() async {
    final lang = LanguageService.instance;
    if (_isActive) {
      await NativeService.stopCaptureService();
      if (!mounted) return;
      setState(() {
        _isActive = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.tr('home_assistant_deactivated')),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      if (!_isLocalModelSelected && _availableQueries <= 0) {
        _showNoQueriesDialog();
        return;
      }

      final hasPermission = await HomeModals.checkAndShowDisclosure(context);
      if (!hasPermission) return;

      final isOptimized = await NativeService.isIgnoringBatteryOptimizations();
      if (!isOptimized && mounted) {
        await HomeModals.showBatteryOptimizationDialog(context);
      }

      bool started = await NativeService.startCaptureService(
        baseUrl: AppConfig.apiBaseUrl,
        sessionToken: _sessionToken,
        mainRole: _selectedMainRole,
        secondaryRole: "Auto",
        autofillRole: "Auto",
        isPremium: true,
        planTier: "plus",
        otpChampions: _selectedOtpChampion,
        activeCreatorId: "",
        language: lang.currentLanguage,
        gameMode: _selectedGameMode,
        modelTier: _selectedModelTier,
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
            content: Text(
              lang.tr('home_assistant_activated'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

  Future<void> _openManualDraft() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualDraftScreen(
          availableQueries: _availableQueries,
          onDataChanged: _fetchUserData,
          onNoQueries: _showNoQueriesDialog,
          initialRole: _selectedMainRole,
          initialMyChampion: _selectedOtpChampion.isNotEmpty ? _selectedOtpChampion : null,
          modelTier: _selectedModelTier,
        ),
      ),
    );
    _fetchUserData();
  }

  /// Abre el Simulador 2D de Esquivo de Habilidades cambiando a la pestaña Game 2D
  Future<void> _openDodgeSimulator() async {
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _visitedTabs.add(2);
      _currentTab = 2;
    });
  }

  void _showOtpChampionPickerModal() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChampionPickerSheet(
        title: 'Tu Campeón Favorito (OTP)',
        selectedChampion: _selectedOtpChampion,
        searchHint: 'Buscar campeón...',
        heightFactor: 0.72,
        leadingHeaderIcon: const Icon(Icons.star_rounded, color: Color(0xFFFDE047), size: 22),
        onClear: _selectedOtpChampion.isNotEmpty
            ? () {
                _updateOtpChampion('');
                Navigator.of(ctx).pop();
              }
            : null,
        onSelected: (champ) {
          _updateOtpChampion(champ);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  /// Envuelve cada pestaña en un contenedor con Lazy Load y control de prioridad de CPU/GPU (`TickerMode`).
  /// Si la pestaña aún no se ha visitado, no se instancia en memoria.
  /// Si la pestaña está oculta o el Simulador 2D está corriendo, sus Tickers se congelan (0% lag).
  Widget _buildPrioritizedTab(int tabIndex, Widget Function() builder) {
    if (!_visitedTabs.contains(tabIndex)) {
      return const SizedBox.shrink();
    }
    final bool isTabActive = !_isHighPriorityGameRunning && _currentTab == tabIndex;
    return TickerMode(
      enabled: isTabActive,
      child: builder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.instance.languageNotifier,
      builder: (context, _, _) {
        return Scaffold(
          key: _scaffoldKey,
          drawer: _buildDrawer(),
          backgroundColor: AppTheme.darkScaffold,
          extendBody: false,
          body: IndexedStack(
            index: _currentTab,
            children: [
              _buildPrioritizedTab(
                0,
                () => ReelsScreen(
                  isTab: true,
                  isActive: _currentTab == 0,
                  userPhotoUrl: _user.userPhotoUrl,
                ),
              ),
              _buildPrioritizedTab(
                1,
                _buildHomeContent,
              ),
              _buildPrioritizedTab(
                2,
                () => DodgeSimulatorScreen(
                  userName: (_user.userName != null && _user.userName!.trim().isNotEmpty)
                      ? _user.userName!
                      : 'Invocador',
                  userPhotoUrl: _user.userPhotoUrl,
                  onExit: () {
                    if (mounted) {
                      setState(() => _currentTab = 1);
                    }
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );
  }

  Widget _buildHomeContent() {
    final lang = LanguageService.instance;
    final langOpt = lang.currentOption;
    final userPhotoUrl = _user.userPhotoUrl;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppTheme.screenBackgroundGradient,
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
                  // Botón Hamburguesa + Logo & Título
                  Row(
                    children: [
                      InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _scaffoldKey.currentState?.openDrawer();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.hextechCyan.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.hextechCyan.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.hextechCyan.withValues(alpha: 0.2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
                        ),
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

                  // Selector Desplegable de Modo de Juego (Wild Rift / LoL PC)
                  Theme(
                    data: Theme.of(context).copyWith(
                      cardColor: AppTheme.surface,
                    ),
                    child: PopupMenuButton<String>(
                      tooltip: 'Modo de Consulta',
                      offset: const Offset(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: (_selectedGameMode == 'wild_rift'
                                  ? AppTheme.hextechCyan
                                  : AppTheme.hextechGold)
                              .withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      color: const Color(0xFF0F172A),
                      onSelected: (mode) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedGameMode = mode);
                        SharedPreferences.getInstance()
                            .then((p) => p.setString('game_mode', mode));
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'wild_rift',
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/images/logo_wild_rift.png',
                                height: 24,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Wild Rift',
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: _selectedGameMode == 'wild_rift'
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: _selectedGameMode == 'wild_rift'
                                      ? AppTheme.hextechCyan
                                      : Colors.white70,
                                ),
                              ),
                              const Spacer(),
                              if (_selectedGameMode == 'wild_rift')
                                const Icon(Icons.check_circle_rounded,
                                    color: AppTheme.hextechCyan, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        PopupMenuItem<String>(
                          value: 'lol_pc',
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/images/logo_lol_pc.png',
                                height: 24,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'LoL PC',
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: _selectedGameMode == 'lol_pc'
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: _selectedGameMode == 'lol_pc'
                                      ? AppTheme.hextechGold
                                      : Colors.white70,
                                ),
                              ),
                              const Spacer(),
                              if (_selectedGameMode == 'lol_pc')
                                const Icon(Icons.check_circle_rounded,
                                    color: AppTheme.hextechGold, size: 18),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (_selectedGameMode == 'wild_rift'
                                  ? AppTheme.hextechCyan
                                  : AppTheme.hextechGold)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: (_selectedGameMode == 'wild_rift'
                                    ? AppTheme.hextechCyan
                                    : AppTheme.hextechGold)
                                .withValues(alpha: 0.4),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_selectedGameMode == 'wild_rift'
                                      ? AppTheme.hextechCyan
                                      : AppTheme.hextechGold)
                                  .withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              _selectedGameMode == 'wild_rift'
                                  ? 'assets/images/logo_wild_rift.png'
                                  : 'assets/images/logo_lol_pc.png',
                              height: 20,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _selectedGameMode == 'wild_rift' ? 'Wild Rift' : 'LoL PC',
                              style: GoogleFonts.outfit(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: _selectedGameMode == 'wild_rift'
                                    ? AppTheme.hextechCyan
                                    : AppTheme.hextechGold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: _selectedGameMode == 'wild_rift'
                                  ? AppTheme.hextechCyan
                                  : AppTheme.hextechGold,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // --- 1.5 BANNER DE ACTUALIZACIÓN AUTOMÁTICA (SI HAY NUEVA VERSIÓN EN GOOGLE PLAY) ---
            ValueListenableBuilder<AppUpdateStatus?>(
              valueListenable: UpdateService.instance.updateStatus,
              builder: (context, updateInfo, _) {
                if (updateInfo == null || !updateInfo.hasUpdate) {
                  return const SizedBox.shrink();
                }
                final bool isReady = updateInfo.isDownloaded;
                final bool isDownloading = updateInfo.isDownloading;
                final Color bannerColor =
                    isReady ? AppTheme.hextechEmerald : AppTheme.hextechCyan;
                final String bannerText = isDownloading
                    ? '${lang.tr("home_update_banner", {"version": updateInfo.latestVersionName})} (${updateInfo.downloadProgress}%)'
                    : lang.tr('home_update_banner', {'version': updateInfo.latestVersionName});

                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: InkWell(
                    onTap: () => UpdateService.instance.onBannerTapped(
                      context,
                      updateInfo,
                      langCode: lang.currentLanguage,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [
                            bannerColor.withValues(alpha: 0.22),
                            AppTheme.hextechEmerald.withValues(alpha: 0.16),
                          ],
                        ),
                        border: Border.all(
                          color: bannerColor.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isReady
                                ? Icons.install_mobile_rounded
                                : Icons.system_update_rounded,
                            color: bannerColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              bannerText,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: bannerColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              lang.tr('home_update_btn'),
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.deepDarkBg,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // --- 1.6 BANNER ROJO EN TIEMPO REAL SI ESTAMOS EN DIRECTO AHORA ---
            if (_liveEvent != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: InkWell(
                  onTap: () {
                    final url = (_liveEvent!['action_url'] ?? '').toString();
                    if (url.isNotEmpty) {
                      NativeService.openExternalUrl(url);
                    } else {
                      _openEventsScreen();
                    }
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.hextechCrimson.withValues(alpha: 0.28),
                          AppTheme.background,
                        ],
                      ),
                      border: Border.all(color: AppTheme.hextechCrimson, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.hextechCrimson,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            lang.tr('home_live_badge'),
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            (_liveEvent!['title'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Icon(Icons.open_in_new_rounded, color: AppTheme.hextechCrimson, size: 17),
                      ],
                    ),
                  ),
                ),
              ),

            // --- 2. MOTOR UNIFICADO: AUREON LOCAL HÍBRIDO (PODA POR ROL + VOZ LOCAL) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.surface.withValues(alpha: 0.75),
                      AppTheme.background.withValues(alpha: 0.9),
                    ],
                  ),
                  border: Border.all(
                    color: AppTheme.hextechEmerald.withValues(alpha: 0.35),
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
                        color: AppTheme.hextechEmerald.withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.memory_rounded,
                        color: AppTheme.hextechEmerald,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Aureon Local • IA Híbrida',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.hextechEmerald.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppTheme.hextechEmerald.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  'ACTIVO',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.hextechEmerald,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _localModelDownloaded
                                ? 'SLM Local (${_localModelSizeMb.toStringAsFixed(0)} MB) + Voz Local'
                                : 'Top 3 + Estrategia + Runas • Voz Local',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _handleLocalModelTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _localModelDownloaded
                              ? AppTheme.hextechEmerald.withValues(alpha: 0.16)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _localModelDownloaded
                                ? AppTheme.hextechEmerald.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: _localModelDownloading
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.hextechEmerald,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$_localModelProgress%',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.hextechEmerald,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _localModelDownloaded
                                        ? Icons.check_circle_outline_rounded
                                        : Icons.download_rounded,
                                    size: 14,
                                    color: _localModelDownloaded
                                        ? AppTheme.hextechEmerald
                                        : Colors.white70,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _localModelDownloaded ? 'GGUF' : 'Bajar IA',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _localModelDownloaded
                                          ? AppTheme.hextechEmerald
                                          : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(flex: 2),

            // --- 3. PROTAGONISTA CENTRAL: ESFERA HEXTECH (WILD RIFT) O ESCÁNER CÁMARA (LOL PC) ---
            Center(
              child: _selectedGameMode == 'wild_rift'
                  ? HextechOrb(
                      isActive: _isActive,
                      onTap: _toggleService,
                    )
                  : HextechOrb(
                      isActive: true,
                      onTap: _openLolPcScanner,
                      label: 'ESCANEAR',
                      icon: Icons.photo_camera_rounded,
                      customOrbColor: AppTheme.accent,
                      customGlowColor: const Color(0xFF0284C7),
                    ),
            ),

            const SizedBox(height: 24),

            // Status indicator below Orb / Scanner
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _selectedGameMode == 'lol_pc'
                    ? AppTheme.accent.withValues(alpha: 0.15)
                    : (_isActive
                        ? AppTheme.hextechEmerald.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _selectedGameMode == 'lol_pc'
                      ? AppTheme.accent.withValues(alpha: 0.4)
                      : (_isActive
                          ? AppTheme.hextechEmerald.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.1)),
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
                      color: _selectedGameMode == 'lol_pc'
                          ? AppTheme.accent
                          : (_isActive ? AppTheme.hextechEmerald : Colors.white54),
                      boxShadow: [
                        BoxShadow(
                          color: (_selectedGameMode == 'lol_pc'
                                  ? AppTheme.accent
                                  : (_isActive ? AppTheme.hextechEmerald : Colors.white24))
                              .withValues(alpha: 0.8),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedGameMode == 'lol_pc'
                        ? 'Apunta la cámara al monitor de tu PC'
                        : (_isActive
                            ? lang.tr('home_status_active')
                            : lang.tr('home_status_idle')),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: _selectedGameMode == 'lol_pc'
                          ? AppTheme.accent
                          : (_isActive ? AppTheme.hextechEmerald : Colors.white70),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --- 3.5 BOTONES DE ACCESO: MODO MANUAL & CAMPEÓN OTP ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openManualDraft,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.hextechCyan,
                        side: BorderSide(color: AppTheme.hextechCyan.withValues(alpha: 0.4), width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: AppTheme.hextechCyan.withValues(alpha: 0.06),
                      ),
                      icon: const Icon(Icons.touch_app_rounded, size: 17),
                      label: Text(
                        'Modo Manual',
                        style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showOtpChampionPickerModal,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _selectedOtpChampion.isNotEmpty
                            ? const Color(0xFFFDE047)
                            : AppTheme.hextechGold,
                        side: BorderSide(
                          color: (_selectedOtpChampion.isNotEmpty
                                  ? const Color(0xFFFDE047)
                                  : AppTheme.hextechGold)
                              .withValues(alpha: 0.45),
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: (_selectedOtpChampion.isNotEmpty
                                ? const Color(0xFFFDE047)
                                : AppTheme.hextechGold)
                            .withValues(alpha: 0.08),
                      ),
                      icon: Icon(
                        _selectedOtpChampion.isNotEmpty ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 18,
                        color: _selectedOtpChampion.isNotEmpty
                            ? const Color(0xFFFDE047)
                            : AppTheme.hextechGold,
                      ),
                      label: Text(
                        _selectedOtpChampion.isNotEmpty
                            ? 'OTP: $_selectedOtpChampion'
                            : 'Campeón OTP',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 2),

            // Bottom footer hint
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Text(
                lang.tr('home_footer_hint'),
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
    );
  }

  Widget _buildBottomNav() {
    final lang = LanguageService.instance;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.deepDarkBg,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.movie_filter_rounded,
                activeColor: AppTheme.hextechCrimson,
                tooltip: 'Breif',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.bolt_rounded,
                activeColor: AppTheme.hextechCyan,
                tooltip: 'Home',
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.sports_esports_rounded,
                activeColor: AppTheme.hextechEmerald,
                tooltip: 'Game 2D',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required Color activeColor,
    required String tooltip,
    bool showBadge = false,
  }) {
    final isSelected = _currentTab == index;
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _visitedTabs.add(index);
              _currentTab = index;
            });
            _fetchUserData();
          },
          splashColor: activeColor.withValues(alpha: 0.08),
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedScale(
                    scale: isSelected ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      icon,
                      color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.4),
                      size: 25,
                    ),
                  ),
                  if (showBadge)
                    Positioned(
                      right: -3,
                      top: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppTheme.hextechCrimson,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.deepDarkBg, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: isSelected ? 16 : 0,
                height: 3,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.7),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
