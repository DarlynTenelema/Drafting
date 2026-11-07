import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/api_client.dart';
import '../core/services/language_service.dart';
import '../core/services/native_service.dart';

class EventsScreen extends StatefulWidget {
  final bool isTab;
  final String? userEmail;
  final ValueChanged<Map<String, dynamic>?>? onLiveEventChanged;

  const EventsScreen({
    super.key,
    this.isTab = true,
    this.userEmail,
    this.onLiveEventChanged,
  });

  @override
  State<EventsScreen> createState() => EventsScreenState();
}

class EventsScreenState extends State<EventsScreen> {
  static const String _authorizedAdminEmail = '0805409802d@gmail.com';

  bool get _isAuthorizedAdmin =>
      (widget.userEmail ?? '').trim().toLowerCase() == _authorizedAdminEmail;
  bool _isLoading = true;
  bool _notificationsEnabled = true;
  Map<String, dynamic>? _liveNow;
  List<dynamic> _events = [];
  List<dynamic> _socialLinks = [];
  Timer? _livePollingTimer;

  @override
  void initState() {
    super.initState();
    _checkNotificationsState();
    _fetchEventsData();
    LanguageService.instance.languageNotifier.addListener(_onLanguageChanged);
    // Sondeo ligero cada 45s para detectar nuevos directos en vivo en tiempo real
    _livePollingTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _fetchEventsData(silent: true);
    });
  }

  void _onLanguageChanged() {
    if (mounted) {
      _fetchEventsData(silent: true);
      setState(() {});
    }
  }

  @override
  void dispose() {
    LanguageService.instance.languageNotifier.removeListener(_onLanguageChanged);
    _livePollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNotificationsState() async {
    final enabled = await NativeService.areNotificationsEnabled();
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
      });
    }
  }

  /// Se invoca cuando el usuario toca por primera vez la pestaña "Eventos"
  Future<void> onTabVisitedFirstTime() async {
    await _checkNotificationsState();
    final prefs = await SharedPreferences.getInstance();
    final alreadyShownModal = prefs.getBool('has_shown_events_notif_modal') ?? false;

    if (!_notificationsEnabled && !alreadyShownModal && mounted) {
      await prefs.setBool('has_shown_events_notif_modal', true);
      if (mounted) {
        _showOneClickNotificationModal();
      }
    }
  }

  Future<void> _fetchEventsData({bool silent = false}) async {
    if (!silent && _events.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = LanguageService.instance.currentLanguage;
      final response = await ApiClient.get('/api/v1/events?lang=$lang', authenticated: false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final Map<String, dynamic>? liveEvent =
            (data['live_now'] is Map<String, dynamic>) ? data['live_now'] as Map<String, dynamic> : null;
        final List<dynamic> eventsList = (data['events'] is List) ? data['events'] as List<dynamic> : [];
        final List<dynamic> socialsList =
            (data['social_links'] is List) ? data['social_links'] as List<dynamic> : [];

        if (mounted) {
          setState(() {
            _liveNow = liveEvent;
            _events = eventsList;
            _socialLinks = socialsList;
            _isLoading = false;
          });
        }

        widget.onLiveEventChanged?.call(liveEvent);

        // Si hay un directo en vivo nuevo que aún no habíamos notificado en el teléfono, lanzar notificación nativa
        if (liveEvent != null) {
          final String liveId = (liveEvent['id'] ?? '').toString();
          final String liveUpdated = (liveEvent['updated_at'] ?? '').toString();
          final String notifKey = '$liveId:$liveUpdated';
          final String lastNotifiedKey = prefs.getString('last_notified_live_event') ?? '';

          if (liveId.isNotEmpty && notifKey != lastNotifiedKey) {
            await prefs.setString('last_notified_live_event', notifKey);
            await NativeService.showEventNotification(
              title: '🔴 ${liveEvent['title'] ?? "¡Drafting está en Directo!"}',
              body: (liveEvent['subtitle'] ?? 'Toca para entrar ahora mismo a la transmisión en vivo.').toString(),
              url: (liveEvent['action_url'] ?? '').toString(),
            );
          }
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error cargando eventos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Modal estilo red social para activar notificaciones con 1 solo clic al entrar a Eventos
  Future<void> _showOneClickNotificationModal() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 26),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFEF4444).withValues(alpha: 0.25),
                        const Color(0xFF00E5FF).withValues(alpha: 0.25),
                      ],
                    ),
                    border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.5)),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFF00E5FF),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  LanguageService.instance.tr('ev_notif_modal_title'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  LanguageService.instance.tr('ev_notif_modal_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: const Color(0xFF090D16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      Navigator.of(ctx).pop();
                      await NativeService.requestNotificationPermission();
                      await Future.delayed(const Duration(milliseconds: 600));
                      await _checkNotificationsState();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            content: Row(
                              children: [
                                const Icon(Icons.notifications_active_rounded, color: Colors.white),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    LanguageService.instance.tr('ev_notif_enabled_snack'),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.bolt_rounded, size: 22),
                    label: Text(
                      LanguageService.instance.tr('ev_notif_modal_btn'),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    LanguageService.instance.tr('not_now'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
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

  Future<void> _openUrlWithOneClick(String url) async {
    String clean = url.trim();
    if (clean.isEmpty) return;
    if (!clean.toLowerCase().startsWith('http://') &&
        !clean.toLowerCase().startsWith('https://') &&
        !clean.toLowerCase().startsWith('market://')) {
      clean = 'https://${clean.replaceFirst(RegExp(r'^/+'), '')}';
    }
    HapticFeedback.selectionClick();
    await NativeService.openExternalUrl(clean);
  }

  Future<void> _deleteEventAsAdmin(String eventId) async {
    if (!_isAuthorizedAdmin || eventId.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    try {
      final res = await ApiClient.post(
        '/api/v1/events/manage',
        authenticated: true,
        body: {
          'action': 'delete_event',
          'event_id': eventId.trim(),
        },
      );
      if (res.statusCode == 200) {
        await _fetchEventsData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF10B981),
              content: Text('Publicación eliminada correctamente.'),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Color _platformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return const Color(0xFFFF0050);
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'discord':
        return const Color(0xFF5865F2);
      case 'x':
      case 'twitter':
        return const Color(0xFF00E5FF);
      case 'twitch':
        return const Color(0xFF9146FF);
      case 'kick':
        return const Color(0xFF53FC18);
      case 'youtube':
        return const Color(0xFFFF0000);
      default:
        return const Color(0xFFC89B3C);
    }
  }

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return Icons.music_note_rounded;
      case 'facebook':
        return Icons.facebook_rounded;
      case 'discord':
        return Icons.forum_rounded;
      case 'x':
      case 'twitter':
        return Icons.alternate_email_rounded;
      case 'twitch':
        return Icons.live_tv_rounded;
      case 'kick':
        return Icons.videocam_rounded;
      case 'youtube':
        return Icons.play_circle_fill_rounded;
      default:
        return Icons.public_rounded;
    }
  }

  String _platformLabel(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return 'TikTok';
      case 'facebook':
        return 'Facebook';
      case 'discord':
        return 'Discord';
      case 'x':
      case 'twitter':
        return 'X (Twitter)';
      case 'twitch':
        return 'Twitch';
      case 'kick':
        return 'Kick';
      case 'youtube':
        return 'YouTube';
      default:
        return platform.toUpperCase();
    }
  }

  /// Panel de Administración Exclusivo para 0805409802d@gmail.com
  void _showAdminPublisherModal() {
    if (!_isAuthorizedAdmin) return;

    final titleCtrl = TextEditingController();
    final subtitleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final badgeCtrl = TextEditingController(text: '🔴 EN DIRECTO AHORA');
    String selectedPlatform = 'tiktok';
    String mode = 'live'; // 'live' | 'event' | 'social'
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFC89B3C)),
                            const SizedBox(width: 8),
                            Text(
                              'Panel Admin • Directos y Redes',
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Selector de Acción
                    Row(
                      children: [
                        _buildAdminModeChip(
                          label: '🔴 Iniciar Directo',
                          selected: mode == 'live',
                          onTap: () => setModalState(() {
                            mode = 'live';
                            badgeCtrl.text = '🔴 EN DIRECTO AHORA';
                          }),
                        ),
                        const SizedBox(width: 8),
                        _buildAdminModeChip(
                          label: '📅 Crear Evento',
                          selected: mode == 'event',
                          onTap: () => setModalState(() {
                            mode = 'event';
                            badgeCtrl.text = 'NUEVA PUBLICACIÓN';
                          }),
                        ),
                        const SizedBox(width: 8),
                        _buildAdminModeChip(
                          label: '🔗 Link de Red',
                          selected: mode == 'social',
                          onTap: () => setModalState(() {
                            mode = 'social';
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPlatform,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white),
                      decoration: _adminInputDecoration('Red Social / Plataforma'),
                      items: const [
                        DropdownMenuItem(value: 'tiktok', child: Text('TikTok (@scxxiii_company)')),
                        DropdownMenuItem(value: 'facebook', child: Text('Facebook Oficial')),
                        DropdownMenuItem(value: 'youtube', child: Text('YouTube (@SCXXIII_Company)')),
                        DropdownMenuItem(value: 'x', child: Text('X (@Darlyn_XXIII)')),
                        DropdownMenuItem(value: 'discord', child: Text('Discord Oficial')),
                        DropdownMenuItem(value: 'twitch', child: Text('Twitch')),
                        DropdownMenuItem(value: 'kick', child: Text('Kick')),
                      ],
                      onChanged: (v) {
                        if (v != null) setModalState(() => selectedPlatform = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _adminInputDecoration(
                        mode == 'social'
                            ? 'Nombre o Usuario (ej. @scxxiii_company)'
                            : 'Título del Directo o Evento',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: subtitleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _adminInputDecoration('Descripción corta para los jugadores'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: urlCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _adminInputDecoration('Enlace directo (https://...)'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (_liveNow != null) ...[
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      setModalState(() => isSubmitting = true);
                                      try {
                                        final res = await ApiClient.post(
                                          '/api/v1/events/manage',
                                          authenticated: true,
                                          body: {
                                            'action': 'stop_all_live',
                                          },
                                        );
                                        if (res.statusCode == 200) {
                                          if (ctx.mounted) Navigator.pop(ctx);
                                          await _fetchEventsData();
                                        }
                                      } catch (_) {}
                                      setModalState(() => isSubmitting = false);
                                    },
                              child: const Text('Apagar Directo'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E5FF),
                              foregroundColor: const Color(0xFF090D16),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    setModalState(() => isSubmitting = true);
                                    try {
                                      final res = await ApiClient.post(
                                        '/api/v1/events/manage',
                                        authenticated: true,
                                        body: {
                                          'action': mode == 'social' ? 'update_social' : 'upsert_event',
                                          'platform': selectedPlatform,
                                          'title': titleCtrl.text.trim(),
                                          'social_handle': titleCtrl.text.trim(),
                                          'subtitle': subtitleCtrl.text.trim(),
                                          'action_url': urlCtrl.text.trim(),
                                          'badge_text': badgeCtrl.text.trim(),
                                          'is_live': mode == 'live',
                                          'event_type': mode,
                                        },
                                      );
                                      if (res.statusCode == 200) {
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        await _fetchEventsData();
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              backgroundColor: Color(0xFF10B981),
                                              content: Text('¡Publicado y sincronizado en vivo!'),
                                            ),
                                          );
                                        }
                                      } else {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: Colors.redAccent,
                                              content: Text(res.body),
                                            ),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      debugPrint('Error admin events: $e');
                                    }
                                    if (ctx.mounted) {
                                      setModalState(() => isSubmitting = false);
                                    }
                                  },
                            icon: const Icon(Icons.publish_rounded, size: 18),
                            label: Text(
                              isSubmitting ? 'Publicando...' : 'Publicar en Vivo',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildAdminModeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFF00E5FF) : Colors.white12,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: selected ? const Color(0xFF00E5FF) : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _adminInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        automaticallyImplyLeading: !widget.isTab,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.podcasts_rounded, color: Color(0xFF00E5FF), size: 22),
            const SizedBox(width: 8),
            Text(
              lang.tr('ev_appbar'),
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _notificationsEnabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_outlined,
              color: _notificationsEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              size: 21,
            ),
            tooltip: 'Notificaciones de Directos',
            onPressed: _showOneClickNotificationModal,
          ),
          if (_isAuthorizedAdmin)
            IconButton(
              icon: const Icon(Icons.tune_rounded, color: Color(0xFFC89B3C), size: 21),
              tooltip: 'Panel Admin Exclusivo',
              onPressed: _showAdminPublisherModal,
            ),
        ],
      ),
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
        child: RefreshIndicator(
          color: const Color(0xFF00E5FF),
          backgroundColor: const Color(0xFF0F172A),
          onRefresh: () => _fetchEventsData(),
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  children: [
                    // 1. Tarjeta de Activación de Notificaciones en 1 Clic (si aún no están activas)
                    if (!_notificationsEnabled) _buildEnableNotificationsBanner(),

                    // 2. Tarjeta Protagonista si hay un Directo en Vivo ahora mismo
                    if (_liveNow != null) ...[
                      _buildLiveNowHeroCard(_liveNow!),
                      const SizedBox(height: 20),
                    ],

                    // 3. Sección: Síguenos en Redes Sociales Oficiales (1 Clic a la App Nativa)
                    Row(
                      children: [
                        const Icon(Icons.share_rounded, color: Color(0xFFC89B3C), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          lang.tr('ev_socials_header'),
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: const Color(0xFFC89B3C),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lang.tr('ev_socials_sub'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSocialNetworksGrid(),

                    const SizedBox(height: 24),

                    // 4. Sección: Eventos, Directos y Noticias Oficiales
                    Row(
                      children: [
                        const Icon(Icons.bolt_rounded, color: Color(0xFF00E5FF), size: 20),
                        const SizedBox(width: 6),
                        Text(
                          lang.tr('ev_feed_header'),
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: const Color(0xFF00E5FF),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._events.map((ev) => _buildEventCard(ev as Map<String, dynamic>)),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEnableNotificationsBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF59E0B).withValues(alpha: 0.2),
            const Color(0xFF0F172A),
          ],
        ),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded, color: Color(0xFFF59E0B), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LanguageService.instance.tr('ev_notif_banner_title'),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  LanguageService.instance.tr('ev_notif_banner_sub'),
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              await NativeService.requestNotificationPermission();
              await Future.delayed(const Duration(milliseconds: 500));
              await _checkNotificationsState();
            },
            child: Text(
              LanguageService.instance.tr('ev_notif_banner_btn'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveNowHeroCard(Map<String, dynamic> live) {
    final String platform = (live['platform'] ?? 'tiktok').toString();
    final String title = (live['title'] ?? '¡Estamos en Directo!').toString();
    final String subtitle = (live['subtitle'] ?? 'Toca para entrar ahora a la transmisión.').toString();
    final String url = (live['action_url'] ?? '').toString();

    return InkWell(
      onTap: () => _openUrlWithOneClick(url),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFEF4444).withValues(alpha: 0.28),
              const Color(0xFF1E293B),
            ],
          ),
          border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.28),
              blurRadius: 18,
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                      const SizedBox(width: 5),
                      Text(
                        '${LanguageService.instance.tr("ev_live_now_tag")} • ${_platformLabel(platform).toUpperCase()}',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_platformIcon(platform), color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    LanguageService.instance.tr('ev_live_join_btn'),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialNetworksGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _socialLinks.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.35,
      ),
      itemBuilder: (context, index) {
        final item = _socialLinks[index] as Map<String, dynamic>;
        final String platform = (item['platform'] ?? '').toString();
        final String name = (item['name'] ?? _platformLabel(platform)).toString();
        final String handle = (item['handle'] ?? '').toString();
        final String url = (item['url'] ?? '').toString();
        final Color color = _platformColor(platform);

        return InkWell(
          onTap: () => _openUrlWithOneClick(url),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF151D2A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.16),
                  ),
                  child: Icon(_platformIcon(platform), color: color, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (handle.isNotEmpty)
                        Text(
                          handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: color),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEventCard(Map<String, dynamic> ev) {
    final String eventId = (ev['id'] ?? '').toString();
    final String platform = (ev['platform'] ?? 'tiktok').toString();
    final String title = (ev['title'] ?? '').toString();
    final String subtitle = (ev['subtitle'] ?? '').toString();
    final String url = (ev['action_url'] ?? '').toString();
    final String badge = (ev['badge_text'] ?? 'EVENTO').toString();
    final String dateText = (ev['event_date_text'] ?? '').toString();
    final bool isLive = ev['is_live'] == true;
    final Color accent = isLive ? const Color(0xFFEF4444) : _platformColor(platform);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openUrlWithOneClick(url),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: isLive ? 0.8 : 0.3),
              width: isLive ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.outfit(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (dateText.isNotEmpty)
                    Text(
                      dateText,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  const Spacer(),
                  if (_isAuthorizedAdmin && eventId.isNotEmpty) ...[
                    InkWell(
                      onTap: () => _deleteEventAsAdmin(eventId),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(_platformIcon(platform), color: accent, size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    isLive
                        ? LanguageService.instance.tr('ev_go_live')
                        : LanguageService.instance.tr('ev_open_in', {'platform': _platformLabel(platform)}),
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new_rounded, color: accent, size: 15),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

