import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_translations.dart';
import '../../shared/widgets/hextech_ui.dart';
import '../../theme/app_theme.dart';
import 'native_service.dart';

class LanguageOption {
  final String code;
  final String badge;
  final String name;
  final String regions;
  final String flag;

  const LanguageOption({
    required this.code,
    required this.badge,
    required this.name,
    required this.regions,
    required this.flag,
  });
}

class LanguageService {
  static final LanguageService instance = LanguageService._internal();
  LanguageService._internal();

  static const String _prefsKey = 'app_language';

  static const List<LanguageOption> supportedLanguages = [
    LanguageOption(
      code: 'es',
      badge: 'ES',
      name: 'Español',
      regions: 'Latinoamérica • España',
      flag: '🇪🇸',
    ),
    LanguageOption(
      code: 'pt',
      badge: 'PT',
      name: 'Português',
      regions: 'Brasil • Portugal',
      flag: '🇧🇷',
    ),
    LanguageOption(
      code: 'en',
      badge: 'EN',
      name: 'English',
      regions: 'United States • United Kingdom',
      flag: '🇺🇸',
    ),
    LanguageOption(
      code: 'fr',
      badge: 'FR',
      name: 'Français',
      regions: 'Canada • France',
      flag: '🇨🇦',
    ),
  ];

  final ValueNotifier<String> languageNotifier = ValueNotifier<String>('es');

  String get currentLanguage => languageNotifier.value;

  LanguageOption get currentOption {
    return supportedLanguages.firstWhere(
      (opt) => opt.code == currentLanguage,
      orElse: () => supportedLanguages.first,
    );
  }

  static String normalizeCode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'es';
    final clean = raw.trim().toLowerCase().split('_').first.split('-').first;
    switch (clean) {
      case 'pt':
        return 'pt';
      case 'en':
        return 'en';
      case 'fr':
        return 'fr';
      case 'es':
      default:
        return 'es';
    }
  }

  /// Inicializa el idioma detectando automáticamente el del teléfono la primera vez
  /// y sincronizándolo con la burbuja nativa de Android.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? saved = prefs.getString(_prefsKey);
      if (saved == null || saved.trim().isEmpty) {
        final sysCode = PlatformDispatcher.instance.locale.languageCode;
        saved = normalizeCode(sysCode);
        await prefs.setString(_prefsKey, saved);
      } else {
        saved = normalizeCode(saved);
      }
      languageNotifier.value = saved;
      await NativeService.setNativeLanguage(saved);
    } catch (_) {
      languageNotifier.value = 'es';
    }
  }

  /// Cambia el idioma en caliente en toda la app Flutter, Backend IA y Burbuja Flotante
  Future<void> setLanguage(String code) async {
    final normalized = normalizeCode(code);
    languageNotifier.value = normalized;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, normalized);
    } catch (_) {}
    await NativeService.setNativeLanguage(normalized);
  }

  /// Traduce una clave según el idioma activo (o uno específico) y reemplaza variables `{var}`
  String tr(String key, [Map<String, String>? params, String? langOverride]) {
    final lang = langOverride != null ? normalizeCode(langOverride) : languageNotifier.value;
    final dict = AppTranslations.dictionary;
    final langMap = dict[lang] ?? dict['es']!;
    String value = langMap[key] ?? dict['es']![key] ?? key;
    if (params != null && params.isNotEmpty) {
      params.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }

  /// Muestra el selector Hextech de idiomas con 1 clic
  Future<void> showLanguagePickerModal(BuildContext context) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return ValueListenableBuilder<String>(
          valueListenable: languageNotifier,
          builder: (context, activeCode, _) {
            return HextechBottomSheetContainer(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HextechSheetHandle(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.hextechCyan.withValues(alpha: 0.15),
                        ),
                        child: const Icon(
                          Icons.translate_rounded,
                          color: AppTheme.hextechCyan,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('lang_modal_title'),
                              style: GoogleFonts.outfit(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              tr('lang_modal_subtitle'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...supportedLanguages.map((opt) {
                    final bool isSelected = opt.code == activeCode;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () async {
                          HapticFeedback.mediumImpact();
                          await setLanguage(opt.code);
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.hextechCyan.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.hextechCyan
                                  : Colors.white.withValues(alpha: 0.1),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(opt.flag, style: const TextStyle(fontSize: 24)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opt.name,
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      opt.regions,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white.withValues(alpha: 0.55),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.hextechCyan,
                                  size: 22,
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    opt.badge,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white54,
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
              ),
            );
          },
        );
      },
    );
  }
}
