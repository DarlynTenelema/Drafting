import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/user_profile.dart';
import '../../core/services/language_service.dart';
import '../../core/services/native_service.dart';
import '../../theme/app_theme.dart';
import 'hextech_ui.dart';

/// Modales y diálogos desacoplados de `IndexScreen` (SRP - Single Responsibility Principle).
/// Conserva al 100% la apariencia original Hextech.
class HomeModals {
  HomeModals._();

  static void showQueriesBreakdown({
    required BuildContext context,
    required UserProfile user,
    required VoidCallback onObtainFreeQueries,
    required VoidCallback onOpenStore,
  }) {
    final lang = LanguageService.instance;
    final q = user.queries;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
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
              const HextechSheetHandle(),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: AppTheme.hextechCyan, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    lang.tr('bd_title', {'count': '${q.available}'}),
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
                iconColor: AppTheme.hextechCyan,
                title: lang.tr('bd_daily_title'),
                value: lang.tr('bd_daily_val', {'count': '${q.daily}'}),
                description: lang.tr('bd_daily_desc'),
              ),
              const SizedBox(height: 12),

              // Item 2: Bono de Bienvenida
              _buildQueryItem(
                icon: Icons.card_giftcard_rounded,
                iconColor: AppTheme.hextechGold,
                title: lang.tr('bd_bonus_title'),
                value: lang.tr('bd_bonus_val', {'count': '${q.bonus}'}),
                description: lang.tr('bd_bonus_desc'),
              ),
              const SizedBox(height: 12),

              // Item 3: Consultas por Recarga
              _buildQueryItem(
                icon: Icons.all_inclusive_rounded,
                iconColor: AppTheme.hextechEmerald,
                title: lang.tr('bd_ad_title'),
                value: lang.tr('bd_ad_val', {'count': '${q.ad}'}),
                description: lang.tr('bd_ad_desc'),
              ),
              if (q.purchased > 0) ...[
                const SizedBox(height: 12),
                _buildQueryItem(
                  icon: Icons.shopping_bag_rounded,
                  iconColor: AppTheme.hextechCyan,
                  title: lang.tr('bd_purchased_title'),
                  value: lang.tr('bd_purchased_val', {'count': '${q.purchased}'}),
                  description: lang.tr('bd_purchased_desc'),
                ),
              ],
              if (user.isSubscribed) ...[
                const SizedBox(height: 12),
                _buildQueryItem(
                  icon: Icons.workspace_premium_rounded,
                  iconColor: AppTheme.hextechGold,
                  title: lang.tr('bd_sub_title', {'plan': user.subscriptionPlan.toUpperCase()}),
                  value: lang.tr('bd_sub_val', {'count': '${q.subscription}'}),
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
                          onObtainFreeQueries();
                        },
                        icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                        label: Text(lang.tr('home_free_plus3')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.hextechEmerald,
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
                          onOpenStore();
                        },
                        icon: const Icon(Icons.storefront_rounded, size: 18),
                        label: Text(lang.tr('bd_store_btn')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.hextechCyan,
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

  static Widget _buildQueryItem({
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

  static void showLogoutDialog({
    required BuildContext context,
    required String? userName,
    required VoidCallback onConfirmLogout,
  }) {
    final lang = LanguageService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(lang.tr('logout_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          lang.tr('logout_body', {'user': userName ?? 'Drafting'}),
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
              onConfirmLogout();
            },
            child: Text(lang.tr('logout_confirm'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  static void showNoQueriesDialog({
    required BuildContext context,
    required VoidCallback onObtainQueries,
  }) {
    final lang = LanguageService.instance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: AppTheme.hextechAmber, size: 28),
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
              backgroundColor: AppTheme.hextechEmerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              onObtainQueries();
            },
            icon: const Icon(Icons.bolt_rounded),
            label: Text(lang.tr('no_queries_btn')),
          ),
        ],
      ),
    );
  }

  static Future<bool> checkAndShowDisclosure(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasAccepted = prefs.getBool('hasAcceptedDisclosure') ?? false;

    if (hasAccepted) {
      return true;
    }

    if (!context.mounted) return false;
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

  static Future<void> showBatteryOptimizationDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final bool alreadyAsked = prefs.getBool('hasAskedBatteryOptimization') ?? false;
    if (alreadyAsked) return;

    if (!context.mounted) return;
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

  static void showSecurityInfoDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.hextechEmerald, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: AppTheme.hextechEmerald, size: 26),
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
                  color: AppTheme.hextechEmerald,
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
              backgroundColor: AppTheme.hextechEmerald,
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
}
