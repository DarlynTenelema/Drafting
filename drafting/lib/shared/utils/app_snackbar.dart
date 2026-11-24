import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Utilidad centralizada para mostrar SnackBars con el estilo Hextech original.
class AppSnackBar {
  AppSnackBar._();

  static void showSuccess(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
    double borderRadius = 12,
    bool useOutfitFont = false,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.hextechEmerald,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
        content: icon != null
            ? Row(
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: useOutfitFont
                          ? GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)
                          : const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              )
            : Text(
                message,
                style: useOutfitFont
                    ? GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)
                    : const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  static void showError(
    BuildContext context,
    String message, {
    bool hideCurrent = true,
    Color backgroundColor = AppTheme.hextechCrimson,
    double borderRadius = 12,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (hideCurrent) {
      messenger.hideCurrentSnackBar();
    }
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
        content: Text(
          message,
          style: GoogleFonts.outfit(color: Colors.white),
        ),
      ),
    );
  }

  static void showInfo(
    BuildContext context,
    String message, {
    bool hideCurrent = true,
    IconData? icon = Icons.info_outline_rounded,
    Color iconColor = AppTheme.hextechCyan,
    double borderRadius = 12,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (hideCurrent) {
      messenger.hideCurrentSnackBar();
    }
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
        content: icon != null
            ? Row(
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              )
            : Text(
                message,
                style: GoogleFonts.outfit(color: Colors.white),
              ),
      ),
    );
  }
}
