import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/widgets/hextech_ui.dart';
import '../../theme/app_theme.dart';
import 'api_client.dart';
import 'language_service.dart';
import 'native_service.dart';

class AppUpdateStatus {
  final int currentVersionCode;
  final String currentVersionName;
  final int latestVersionCode;
  final String latestVersionName;
  final int minRequiredVersionCode;
  final bool hasUpdate;
  final bool forceUpdate;
  final String updateMode; // "flexible" | "immediate"
  final String playStoreUrl;
  final String releaseNotes;
  final Map<String, String> releaseNotesI18n;
  final bool isDownloading;
  final int downloadProgress;
  final bool isDownloaded;

  const AppUpdateStatus({
    required this.currentVersionCode,
    required this.currentVersionName,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.minRequiredVersionCode,
    required this.hasUpdate,
    required this.forceUpdate,
    required this.updateMode,
    required this.playStoreUrl,
    required this.releaseNotes,
    required this.releaseNotesI18n,
    this.isDownloading = false,
    this.downloadProgress = 0,
    this.isDownloaded = false,
  });

  AppUpdateStatus copyWith({
    bool? isDownloading,
    int? downloadProgress,
    bool? isDownloaded,
  }) {
    return AppUpdateStatus(
      currentVersionCode: currentVersionCode,
      currentVersionName: currentVersionName,
      latestVersionCode: latestVersionCode,
      latestVersionName: latestVersionName,
      minRequiredVersionCode: minRequiredVersionCode,
      hasUpdate: hasUpdate,
      forceUpdate: forceUpdate,
      updateMode: updateMode,
      playStoreUrl: playStoreUrl,
      releaseNotes: releaseNotes,
      releaseNotesI18n: releaseNotesI18n,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  String localizedNotes(String langCode) {
    final clean = LanguageService.normalizeCode(langCode);
    return releaseNotesI18n[clean] ?? releaseNotes;
  }
}

class UpdateService {
  static final UpdateService instance = UpdateService._internal();
  UpdateService._internal();

  final ValueNotifier<AppUpdateStatus?> updateStatus = ValueNotifier<AppUpdateStatus?>(null);
  bool _hasTriggeredAutoFlexibleInSession = false;
  bool _hasShownDownloadedSnackInSession = false;
  bool _isDialogOpen = false;
  bool _isChecking = false;

  /// Verifica tanto contra Google Play In-App Updates API como contra el Backend si existe una versión nueva
  Future<AppUpdateStatus?> checkForUpdates({
    Map<String, dynamic>? serverVersionPayload,
    String langCode = 'es',
  }) async {
    if (_isChecking && updateStatus.value != null) {
      return updateStatus.value;
    }
    _isChecking = true;

    try {
      final results = await Future.wait([
        NativeService.getAppVersion(),
        NativeService.checkPlayInAppUpdate(),
      ]);

      final pkgInfo = results[0];
      final playInfo = results[1];

      final int localCode = (pkgInfo['versionCode'] is int) ? pkgInfo['versionCode'] as int : 38;
      final String localName = (pkgInfo['versionName'] ?? '1.0.6').toString();

      final bool playHasUpdate = playInfo['updateAvailable'] == true;
      final int playAvailableCode =
          (playInfo['availableVersionCode'] is int) ? playInfo['availableVersionCode'] as int : 0;
      final bool playIsDownloaded = playInfo['isDownloaded'] == true;

      Map<String, dynamic>? data = serverVersionPayload;
      if (data == null) {
        try {
          final response = await ApiClient.get(
            '/api/v1/app/version?version_code=$localCode&lang=$langCode',
            authenticated: false,
          );
          if (response.statusCode == 200) {
            data = jsonDecode(response.body) as Map<String, dynamic>;
          }
        } catch (_) {}
      }

      final int serverLatestCode = (data != null && data['latest_version_code'] is int)
          ? data['latest_version_code'] as int
          : localCode;
      final int latestCode = math.max(serverLatestCode, playAvailableCode);

      final String latestName = (data != null && data['latest_version_name'] != null)
          ? data['latest_version_name'].toString()
          : (latestCode > localCode ? '$localName+' : localName);

      final int minRequiredCode = (data != null && data['min_required_version_code'] is int)
          ? data['min_required_version_code'] as int
          : localCode;

      final bool serverForce = data != null && data['force_update'] == true;
      final bool mustForce = serverForce || localCode < minRequiredCode;
      final bool hasUpdate =
          localCode < latestCode || playHasUpdate || playIsDownloaded || mustForce;

      final String mode = mustForce
          ? 'immediate'
          : (data != null && data['update_mode'] != null
              ? data['update_mode'].toString()
              : 'flexible');

      final String storeUrl = (data != null && data['play_store_url'] != null)
          ? data['play_store_url'].toString()
          : 'https://play.google.com/store/apps/details?id=com.drafting.app';

      final String defaultNotes =
          (data != null && data['release_notes'] != null) ? data['release_notes'].toString() : '';

      final Map<String, String> notesMap = {};
      if (data != null && data['release_notes_i18n'] is Map) {
        (data['release_notes_i18n'] as Map).forEach((k, v) {
          if (v != null) notesMap[k.toString()] = v.toString();
        });
      }

      final prev = updateStatus.value;
      final status = AppUpdateStatus(
        currentVersionCode: localCode,
        currentVersionName: localName,
        latestVersionCode: latestCode,
        latestVersionName: latestName,
        minRequiredVersionCode: minRequiredCode,
        hasUpdate: hasUpdate,
        forceUpdate: mustForce,
        updateMode: mode,
        playStoreUrl: storeUrl,
        releaseNotes: defaultNotes,
        releaseNotesI18n: notesMap,
        isDownloading: playIsDownloaded ? false : (prev?.isDownloading ?? false),
        downloadProgress: playIsDownloaded ? 100 : (prev?.downloadProgress ?? 0),
        isDownloaded: playIsDownloaded || (prev?.isDownloaded ?? false),
      );

      updateStatus.value = status;
      return status;
    } catch (e) {
      debugPrint('⚠️ Error verificando actualización automática: $e');
      return updateStatus.value;
    } finally {
      _isChecking = false;
    }
  }

  /// Verifica y gestiona automáticamente la actualización
  Future<void> checkAndPromptIfNeeded(
    BuildContext context, {
    Map<String, dynamic>? serverVersionPayload,
    String langCode = 'es',
  }) async {
    final status = await checkForUpdates(
      serverVersionPayload: serverVersionPayload,
      langCode: langCode,
    );

    if (status == null || !status.hasUpdate) return;
    if (!context.mounted) return;

    // Caso 1: La actualización ya se descargó en segundo plano
    if (status.isDownloaded) {
      if (status.forceUpdate) {
        await NativeService.completeInAppUpdate();
      } else if (!_hasShownDownloadedSnackInSession) {
        _hasShownDownloadedSnackInSession = true;
        _showDownloadedReadySnackBar(context, langCode: langCode);
      }
      return;
    }

    // Caso 2: Actualización normal (Flexible) -> Descarga silenciosa en 2do plano
    if (!status.forceUpdate) {
      if (!_hasTriggeredAutoFlexibleInSession) {
        _hasTriggeredAutoFlexibleInSession = true;
        await NativeService.startInAppUpdate(
          mode: 'flexible',
          openStoreFallback: false,
          fallbackUrl: status.playStoreUrl,
        );
      }
      return;
    }

    // Caso 3: Actualización crítica/obligatoria (Immediate)
    await NativeService.startInAppUpdate(
      mode: 'immediate',
      openStoreFallback: false,
      fallbackUrl: status.playStoreUrl,
    );

    if (context.mounted && !_isDialogOpen) {
      await showUpdateModal(context, status, langCode: langCode);
    }
  }

  /// Recibe eventos en tiempo real desde MainActivity (descarga en 2do plano en progreso o completada)
  void handleNativeUpdateEvent(
    Map<dynamic, dynamic> event,
    BuildContext context, {
    String langCode = 'es',
  }) {
    final int code = (event['code'] is int) ? event['code'] as int : 0;
    final current = updateStatus.value;

    if (code == 204) {
      final int progress = (event['progress'] is int) ? event['progress'] as int : 0;
      if (current != null) {
        updateStatus.value = current.copyWith(
          isDownloading: true,
          downloadProgress: progress,
          isDownloaded: false,
        );
      }
    } else if (code == 205) {
      if (current != null) {
        updateStatus.value = current.copyWith(
          isDownloading: false,
          downloadProgress: 100,
          isDownloaded: true,
        );
        if (current.forceUpdate) {
          NativeService.completeInAppUpdate();
          return;
        }
      }
      if (context.mounted && !_hasShownDownloadedSnackInSession) {
        _hasShownDownloadedSnackInSession = true;
        _showDownloadedReadySnackBar(context, langCode: langCode);
      }
    }
  }

  void _showDownloadedReadySnackBar(BuildContext context, {String langCode = 'es'}) {
    if (!context.mounted) return;
    final lang = LanguageService.instance;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.background,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.hextechEmerald, width: 1.2),
        ),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.hextechEmerald, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                lang.tr('upd_snack_downloaded', null, langCode),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: lang.tr('upd_btn_install_now', null, langCode),
          textColor: AppTheme.hextechCyan,
          onPressed: () {
            HapticFeedback.mediumImpact();
            NativeService.completeInAppUpdate();
          },
        ),
      ),
    );
  }

  /// Acción rápida al tocar el banner superior del Home
  Future<void> onBannerTapped(
    BuildContext context,
    AppUpdateStatus status, {
    String langCode = 'es',
  }) async {
    HapticFeedback.selectionClick();
    if (status.isDownloaded) {
      await NativeService.completeInAppUpdate();
      return;
    }
    await showUpdateModal(context, status, langCode: langCode);
  }

  /// Abre el modal Hextech de actualización automática con 1 clic
  Future<void> showUpdateModal(
    BuildContext context,
    AppUpdateStatus status, {
    String langCode = 'es',
  }) async {
    if (_isDialogOpen || !context.mounted) return;
    _isDialogOpen = true;

    final lang = LanguageService.instance;
    final notes = status.localizedNotes(langCode);

    await showModalBottomSheet(
      context: context,
      isDismissible: !status.forceUpdate,
      enableDrag: !status.forceUpdate,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return PopScope(
          canPop: !status.forceUpdate,
          child: HextechBottomSheetContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HextechSheetHandle(width: 42),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppTheme.hextechCyan, AppTheme.hextechBlue],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.hextechCyan.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.hextechEmerald.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.hextechEmerald.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              'v${status.latestVersionName} (+${status.latestVersionCode})',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.hextechEmerald,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            lang.tr(
                              status.forceUpdate ? 'upd_title_force' : 'upd_title_flex',
                              null,
                              langCode,
                            ),
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  lang.tr('upd_subtitle', null, langCode),
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lang.tr('upd_whats_new', null, langCode),
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                            color: AppTheme.hextechGold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          notes,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.hextechCyan,
                      foregroundColor: AppTheme.deepDarkBg,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      if (!status.forceUpdate && ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                      if (status.isDownloaded) {
                        await NativeService.completeInAppUpdate();
                      } else {
                        await NativeService.startInAppUpdate(
                          mode: status.forceUpdate ? 'immediate' : 'flexible',
                          openStoreFallback: true,
                          fallbackUrl: status.playStoreUrl,
                        );
                      }
                    },
                    icon: Icon(
                      status.isDownloaded ? Icons.install_mobile_rounded : Icons.download_rounded,
                      size: 22,
                    ),
                    label: Text(
                      lang.tr(
                        status.isDownloaded ? 'upd_btn_install_now' : 'upd_btn_update',
                        null,
                        langCode,
                      ),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (!status.forceUpdate) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt(
                          'dismissed_update_version_code',
                          status.latestVersionCode,
                        );
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                      },
                      child: Text(
                        lang.tr('upd_btn_later', null, langCode),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    _isDialogOpen = false;
  }
}
