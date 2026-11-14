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
import '../core/services/ad_service.dart';
import '../core/services/api_client.dart';
import '../core/services/language_service.dart';
import '../core/services/native_service.dart';
import '../core/services/session_service.dart';
import '../core/services/update_service.dart';
import '../shared/widgets/hextech_orb.dart';
import '../theme/app_theme.dart';
import '../core/constants/app_constants.dart';
import '../widgets/tutorial_dialog.dart';
import 'achievements_screen.dart';
import 'donations_screen.dart';
import 'events_screen.dart';
import 'login_screen.dart';
import 'manual_draft_screen.dart';
import 'store_screen.dart';
import 'trivia_screen.dart';
import 'lol_pc_scanner_screen.dart';

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
  StreamSubscription? _eventSubscription;
  late String _sessionToken;

  bool _isActive = false;
  int _availableQueries = 13;
  int _dailyQueries = 3;
  int _bonusQueries = 10;
  int _adQueries = 0;
  int _purchasedQueries = 0;
  int _subscriptionQueries = 0;
  String _subscriptionPlan = 'none';
  bool _isSubscribed = false;
  String _selectedGameMode = 'wild_rift'; // 'wild_rift' o 'lol_pc'
  String _selectedMainRole = 'Mid';
  String _selectedOtpChampion = '';

  bool _isLoadingQueries = false;
  String? _userName;
  String? _userEmail;
  String? _userPhotoUrl;
  String? _referralCode;
  int _referralCount = 0;
  int _referralRewardsClaimed = 0;
  bool _hasRedeemedReferral = false;

  final GlobalKey<EventsScreenState> _eventsKey = GlobalKey<EventsScreenState>();
  Map<String, dynamic>? _liveEvent;

  /// Control de visibilidad de la pestaña de Donaciones (oculto temporalmente para lanzamiento)
  static const bool showDonationsTab = false;

  int _currentTab = 2; // 0: Eventos, 1: Logros, 2: Home, 3: Trivia, 4: Tienda (o 4: Donaciones, 5: Tienda si showDonationsTab=true)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionToken = widget.sessionToken;
    _loadCachedState();
    _fetchUserData();
    _listenToNativeEvents();
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
        _availableQueries = prefs.getInt('available_queries') ?? 13;
        _dailyQueries = prefs.getInt('daily_queries') ?? 3;
        _bonusQueries = prefs.getInt('bonus_queries') ?? 10;
        _adQueries = prefs.getInt('ad_queries') ?? 0;
        _purchasedQueries = prefs.getInt('purchased_queries') ?? 0;
        _subscriptionQueries = prefs.getInt('subscription_queries') ?? 0;
        _subscriptionPlan = prefs.getString('subscription_plan') ?? 'none';
        _isSubscribed = prefs.getBool('is_subscribed') ?? false;
        _userEmail = prefs.getString('user_email');
        _selectedMainRole = prefs.getString('selected_main_role') ?? 'Mid';
        _selectedOtpChampion = prefs.getString('selected_otp_champion') ?? '';
      });
    }
  }

  Future<void> _updateSelectedRole(String role) async {
    HapticFeedback.selectionClick();
    setState(() => _selectedMainRole = role);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_main_role', role);
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
          _availableQueries = 0;
        });
        _showNoQueriesDialog();
      } else if (code == 204 || code == 205) {
        // Eventos de Google Play In-App Update en segundo plano (descargando / descargado)
        UpdateService.instance.handleNativeUpdateEvent(
          event,
          context,
          langCode: LanguageService.instance.currentLanguage,
        );
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
      } else if (_subscriptionQueries > 0) {
        _subscriptionQueries--;
      } else if (_bonusQueries > 0) {
        _bonusQueries--;
      } else if (_adQueries > 0) {
        _adQueries--;
      } else if (_purchasedQueries > 0) {
        _purchasedQueries--;
      }
    });
    await prefs.setInt('available_queries', _availableQueries);
    await prefs.setInt('daily_queries', _dailyQueries);
    await prefs.setInt('subscription_queries', _subscriptionQueries);
    await prefs.setInt('bonus_queries', _bonusQueries);
    await prefs.setInt('ad_queries', _adQueries);
    await prefs.setInt('purchased_queries', _purchasedQueries);

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
        final data = jsonDecode(response.body);
        if (mounted) {
          final serverQueries = data['available_queries'];
          final prefs = await SharedPreferences.getInstance();
          final dailyGranted = data['daily_reward_granted'] == true;
          setState(() {
            _userName = data['username'] ?? 'Jugador';
            _userEmail = data['email']?.toString();
            _userPhotoUrl = data['profile_pic'];
            if (_userEmail != null) {
              prefs.setString('user_email', _userEmail!);
            }
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
            if (data['purchased_queries'] is int) {
              _purchasedQueries = data['purchased_queries'];
              prefs.setInt('purchased_queries', _purchasedQueries);
            }
            if (data['subscription_queries'] is int) {
              _subscriptionQueries = data['subscription_queries'];
              prefs.setInt('subscription_queries', _subscriptionQueries);
            }
            if (data['subscription_plan'] is String) {
              _subscriptionPlan = data['subscription_plan'];
              prefs.setString('subscription_plan', _subscriptionPlan);
            }
            _isSubscribed = data['is_premium'] == true || data['is_subscribed'] == true;
            prefs.setBool('is_subscribed', _isSubscribed);
          });

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
                backgroundColor: const Color(0xFF00E5FF),
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
    setState(() => _currentTab = showDonationsTab ? 5 : 4);
  }

  void _showQueriesBreakdownDialog() {
    final lang = LanguageService.instance;
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
                    lang.tr('bd_title', {'count': '$_availableQueries'}),
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
                lang.tr('bd_subtitle'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
              const SizedBox(height: 16),

              // Item 1: Consultas Diarias
              _buildQueryItem(
                icon: Icons.calendar_today_rounded,
                iconColor: const Color(0xFF00E5FF),
                title: lang.tr('bd_daily_title'),
                value: lang.tr('bd_daily_val', {'count': '$_dailyQueries'}),
                description: lang.tr('bd_daily_desc'),
              ),
              const SizedBox(height: 12),

              // Item 2: Bono de Bienvenida
              _buildQueryItem(
                icon: Icons.card_giftcard_rounded,
                iconColor: const Color(0xFFC89B3C),
                title: lang.tr('bd_bonus_title'),
                value: lang.tr('bd_bonus_val', {'count': '$_bonusQueries'}),
                description: lang.tr('bd_bonus_desc'),
              ),
              const SizedBox(height: 12),

              // Item 3: Consultas por Recarga
              _buildQueryItem(
                icon: Icons.all_inclusive_rounded,
                iconColor: const Color(0xFF10B981),
                title: lang.tr('bd_ad_title'),
                value: lang.tr('bd_ad_val', {'count': '$_adQueries'}),
                description: lang.tr('bd_ad_desc'),
              ),
              if (_purchasedQueries > 0) ...[
                const SizedBox(height: 12),
                _buildQueryItem(
                  icon: Icons.shopping_bag_rounded,
                  iconColor: const Color(0xFF00E5FF),
                  title: lang.tr('bd_purchased_title'),
                  value: lang.tr('bd_purchased_val', {'count': '$_purchasedQueries'}),
                  description: lang.tr('bd_purchased_desc'),
                ),
              ],
              if (_isSubscribed) ...[
                const SizedBox(height: 12),
                _buildQueryItem(
                  icon: Icons.workspace_premium_rounded,
                  iconColor: const Color(0xFFC89B3C),
                  title: lang.tr('bd_sub_title', {'plan': _subscriptionPlan.toUpperCase()}),
                  value: lang.tr('bd_sub_val', {'count': '$_subscriptionQueries'}),
                  description: lang.tr('bd_sub_desc'),
                ),
              ],
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _obtainQueries();
                        },
                        icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                        label: Text(lang.tr('home_free_plus3')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openStoreScreen();
                        },
                        icon: const Icon(Icons.storefront_rounded, size: 18),
                        label: Text(lang.tr('bd_store_btn')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                ],
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
    final lang = LanguageService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(lang.tr('logout_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          lang.tr('logout_body', {'user': _userName ?? 'Drafting'}),
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(lang.tr('cancel'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(ctx).pop();
              _handleLogout();
            },
            child: Text(lang.tr('logout_confirm'), style: const TextStyle(color: Colors.white)),
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

    AdService.showRewardedAd(
      onUserEarnedReward: () async {
        try {
          final response = await ApiClient.post('/api/v1/user/obtain-queries', authenticated: true);
          int added = 3;

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
          } else if (response.statusCode == 429) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFFEF4444),
                  behavior: SnackBarBehavior.floating,
                  content: Text(LanguageService.instance.tr('home_wait_15s')),
                ),
              );
            }
            return;
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
    final lang = LanguageService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 28),
            const SizedBox(width: 8),
            Text(lang.tr('no_queries_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          lang.tr('no_queries_body'),
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(lang.tr('cancel'), style: const TextStyle(color: Colors.grey)),
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
            label: Text(lang.tr('no_queries_btn')),
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
    final lang = LanguageService.instance;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            lang.tr('disclosure_title'),
            style: const TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold),
          ),
          content: Text(
            lang.tr('disclosure_body'),
            style: const TextStyle(color: AppTheme.textMuted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(lang.tr('disclosure_reject'), style: const TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(lang.tr('disclosure_accept'), style: const TextStyle(color: Colors.white)),
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

  Future<void> _showBatteryOptimizationDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final bool alreadyAsked = prefs.getBool('hasAskedBatteryOptimization') ?? false;
    if (alreadyAsked) return;

    if (!mounted) return;
    final lang = LanguageService.instance;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.bolt, color: Colors.amber, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lang.tr('battery_title'),
                  style: const TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Text(
            lang.tr('battery_body'),
            style: const TextStyle(color: AppTheme.textMuted, height: 1.4, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(lang.tr('not_now'), style: const TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(lang.tr('allow'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    await prefs.setBool('hasAskedBatteryOptimization', true);
    if (proceed == true) {
      await NativeService.requestIgnoreBatteryOptimizations();
    }
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
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 82,
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
          backgroundColor: const Color(0xFFEF4444),
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
      if (_availableQueries <= 0) {
        _showNoQueriesDialog();
        return;
      }

      final hasPermission = await _checkAndShowDisclosure();
      if (!hasPermission) return;

      final isOptimized = await NativeService.isIgnoringBatteryOptimizations();
      if (!isOptimized) {
        await _showBatteryOptimizationDialog();
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
        ),
      ),
    );
    _fetchUserData();
  }

  void _showSecurityInfoDialog() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '100% Seguro & Anti-Ban',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '¿Drafting puede causar ban en Wild Rift?',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF10B981),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'NO. Drafting cumple estrictamente con las políticas de Riot Games para herramientas complementarias:\n\n'
                '• NO inyecta código ni modifica archivos de Wild Rift.\n'
                '• NO accede a la memoria interna del juego.\n'
                '• Funciona como una guía estratégica externa (igual que Porofessor o Blitz en PC).\n\n'
                'Además, si prefieres no usar la burbuja flotante, puedes usar el Modo Manual sin permisos de pantalla.',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showOtpChampionPickerModal() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String search = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = search.isEmpty
                ? AppConstants.wildRiftChampions
                : AppConstants.wildRiftChampions
                    .where((c) => c.toLowerCase().contains(search.toLowerCase()))
                    .toList();
            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
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
                        const Icon(Icons.star_rounded, color: Color(0xFFFDE047), size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tu Campeón Favorito (OTP)',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (_selectedOtpChampion.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              _updateOtpChampion('');
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Limpiar', style: TextStyle(color: Colors.redAccent)),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: TextField(
                      onChanged: (val) => setModalState(() => search = val),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar campeón...',
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
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
                        final champ = filtered[idx];
                        final isSelected = champ == _selectedOtpChampion;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF1E293B),
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
                            style: TextStyle(
                              color: isSelected ? const Color(0xFF00E5FF) : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5FF)) : null,
                          onTap: () {
                            _updateOtpChampion(champ);
                            Navigator.of(ctx).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRoleChip(String id, String label, IconData icon) {
    final isSelected = _selectedMainRole.toLowerCase().contains(id.toLowerCase()) || _selectedMainRole == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => _updateSelectedRole(id),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00E5FF).withValues(alpha: 0.15) : const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white10,
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? const Color(0xFF00E5FF) : Colors.white60,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.instance.languageNotifier,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: const Color(0xFF0B0E14),
          extendBody: false,
          body: IndexedStack(
            index: _currentTab,
            children: [
              EventsScreen(
                key: _eventsKey,
                isTab: true,
                userEmail: _userEmail,
                onLiveEventChanged: (live) {
                  if (mounted) {
                    setState(() => _liveEvent = live);
                  }
                },
              ),
              AchievementsScreen(
                referralCode: _referralCode ?? '',
                referralCount: _referralCount,
                referralRewardsClaimed: _referralRewardsClaimed,
                hasRedeemedReferral: _hasRedeemedReferral,
                onDataChanged: _fetchUserData,
                isTab: true,
              ),
              _buildHomeContent(),
              TriviaScreen(
                onLivesChanged: _fetchUserData,
                isTab: true,
              ),
              if (showDonationsTab)
                DonationsScreen(
                  onDataChanged: _fetchUserData,
                  isTab: true,
                ),
              StoreScreen(
                onDataChanged: _fetchUserData,
                isTab: true,
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
    return Container(
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

                    // Actions: Language Selector, Tutorial & User Profile Avatar (Compact)
                    Row(
                      children: [
                        // Selector de Idioma (ES / PT / EN / FR)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () => lang.showLanguagePickerModal(context),
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(langOpt.flag, style: const TextStyle(fontSize: 13.5)),
                                  const SizedBox(width: 4),
                                  Text(
                                    langOpt.badge,
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                            tooltip: lang.tr('tut_header'),
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
                      isReady ? const Color(0xFF10B981) : const Color(0xFF00E5FF);
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
                              const Color(0xFF10B981).withValues(alpha: 0.16),
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
                                  color: const Color(0xFF090D16),
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
                        setState(() => _currentTab = 0);
                      }
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFEF4444).withValues(alpha: 0.28),
                            const Color(0xFF0F172A),
                          ],
                        ),
                        border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
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
                          const Icon(Icons.open_in_new_rounded, color: Color(0xFFEF4444), size: 17),
                        ],
                      ),
                    ),
                  ),
                ),

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
                                    '$_availableQueries ${_availableQueries == 1 ? lang.tr("home_query_singular") : lang.tr("home_query_plural")}',
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
                                lang.tr('home_tap_breakdown'),
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
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.add_rounded, size: 18),
                                  const SizedBox(width: 4),
                                  Text(lang.tr('home_free_plus3'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              // --- 2.2 INSIGNIA 100% SEGURO Y CUMPLE POLÍTICAS DE RIOT GAMES ---
              Center(
                child: InkWell(
                  onTap: _showSecurityInfoDialog,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 13),
                        const SizedBox(width: 6),
                        Text(
                          '100% Seguro • Cumple políticas de Riot Games',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF6EE7B7),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.info_outline_rounded, color: Color(0xFF6EE7B7), size: 11),
                      ],
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // --- 2.5 SELECTOR DE SISTEMA: (Wild Rift) (LoL PC) ---
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2E).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedGameMode = 'wild_rift');
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _selectedGameMode == 'wild_rift'
                                ? const Color(0xFF00E5FF).withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _selectedGameMode == 'wild_rift'
                                  ? const Color(0xFF00E5FF)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                            boxShadow: _selectedGameMode == 'wild_rift'
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 250),
                              opacity: _selectedGameMode == 'wild_rift' ? 1.0 : 0.45,
                              child: Image.asset(
                                'assets/images/logo_wild_rift.png',
                                height: 38,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedGameMode = 'lol_pc');
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _selectedGameMode == 'lol_pc'
                                ? const Color(0xFFC89B3C).withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _selectedGameMode == 'lol_pc'
                                  ? const Color(0xFFC89B3C)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                            boxShadow: _selectedGameMode == 'lol_pc'
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFC89B3C).withValues(alpha: 0.25),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 250),
                              opacity: _selectedGameMode == 'lol_pc' ? 1.0 : 0.45,
                              child: Image.asset(
                                'assets/images/logo_lol_pc.png',
                                height: 38,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // --- 2.8 SELECTOR DE ROL ACTIVO EN PARTIDA & MODO OTP ---
              if (_selectedGameMode == 'wild_rift') ...[
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TU ROL EN PARTIDA:',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white54,
                              letterSpacing: 0.8,
                            ),
                          ),
                          InkWell(
                            onTap: _showOtpChampionPickerModal,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _selectedOtpChampion.isNotEmpty
                                    ? const Color(0xFFC89B3C).withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _selectedOtpChampion.isNotEmpty
                                      ? const Color(0xFFC89B3C)
                                      : Colors.white12,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    size: 13,
                                    color: _selectedOtpChampion.isNotEmpty
                                        ? const Color(0xFFFDE047)
                                        : Colors.white38,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _selectedOtpChampion.isNotEmpty
                                        ? 'OTP: $_selectedOtpChampion'
                                        : '+ OTP / Mi Champ',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _selectedOtpChampion.isNotEmpty
                                          ? const Color(0xFFFDE047)
                                          : Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildRoleChip('Top', 'Solo / Top', Icons.shield_outlined),
                            _buildRoleChip('Jungle', 'Jungla', Icons.park_outlined),
                            _buildRoleChip('Mid', 'Mid', Icons.bolt_rounded),
                            _buildRoleChip('ADC', 'Dúo / ADC', Icons.crisis_alert_rounded),
                            _buildRoleChip('Support', 'Soporte', Icons.favorite_border_rounded),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

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
                        customOrbColor: const Color(0xFF38BDF8),
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
                      ? const Color(0xFF38BDF8).withValues(alpha: 0.15)
                      : (_isActive
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _selectedGameMode == 'lol_pc'
                        ? const Color(0xFF38BDF8).withValues(alpha: 0.4)
                        : (_isActive
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
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
                            ? const Color(0xFF38BDF8)
                            : (_isActive ? const Color(0xFF10B981) : Colors.white54),
                        boxShadow: [
                          BoxShadow(
                            color: (_selectedGameMode == 'lol_pc'
                                    ? const Color(0xFF38BDF8)
                                    : (_isActive ? const Color(0xFF10B981) : Colors.white24))
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
                            ? const Color(0xFF38BDF8)
                            : (_isActive ? const Color(0xFF10B981) : Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // --- 3.5 BOTÓN DE ACCESO AL MODO MANUAL TÁCTICO (ANTI-BAN / IPAD) ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: OutlinedButton.icon(
                  onPressed: _openManualDraft,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.06),
                  ),
                  icon: const Icon(Icons.touch_app_rounded, size: 18),
                  label: Text(
                    'Modo Manual Táctico (Anti-Ban / iPad)',
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
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
        color: const Color(0xFF090D16),
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
                icon: Icons.podcasts_rounded,
                activeColor: const Color(0xFFEF4444),
                tooltip: lang.tr('nav_events'),
                showBadge: _liveEvent != null,
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.emoji_events_rounded,
                activeColor: const Color(0xFF10B981),
                tooltip: lang.tr('nav_achievements'),
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.bolt_rounded,
                activeColor: const Color(0xFF00E5FF),
                tooltip: lang.tr('nav_home'),
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.quiz_rounded,
                activeColor: const Color(0xFFA855F7),
                tooltip: lang.tr('nav_trivia'),
              ),
              if (showDonationsTab)
                _buildNavItem(
                  index: 4,
                  icon: Icons.volunteer_activism_rounded,
                  activeColor: const Color(0xFFFF0050),
                  tooltip: lang.tr('nav_donations'),
                ),
              _buildNavItem(
                index: showDonationsTab ? 5 : 4,
                icon: Icons.storefront_rounded,
                activeColor: const Color(0xFFC89B3C),
                tooltip: lang.tr('nav_store'),
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
            setState(() => _currentTab = index);
            if (index == 0) {
              _eventsKey.currentState?.onTabVisitedFirstTime();
            }
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
                          color: const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF090D16), width: 1.5),
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
