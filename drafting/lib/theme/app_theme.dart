import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Base Colors
  static const Color background = Color(0xFF0F172A); // Slate 900
  static const Color surface = Color(0xFF1E293B); // Slate 800
  static const Color primary = Color(0xFF3B82F6); // Blue 500
  static const Color primaryDark = Color(0xFF2563EB); // Blue 600
  static const Color textLight = Color(0xFFF8FAFC); // Slate 50
  static const Color textMuted = Color(0xFF94A3B8); // Slate 400
  static const Color accent = Color(0xFF38BDF8); // Light Blue

  // Hextech Design System Palette (Internal standardization, identical hex values)
  static const Color hextechCyan = Color(0xFF00E5FF);
  static const Color hextechBlue = Color(0xFF0052D4);
  static const Color hextechGold = Color(0xFFC89B3C);
  static const Color hextechEmerald = Color(0xFF10B981);
  static const Color hextechCrimson = Color(0xFFEF4444);
  static const Color hextechAmber = Color(0xFFF59E0B);
  static const Color hextechPurple = Color(0xFF8B5CF6);
  static const Color hextechPink = Color(0xFFFF0050);

  static const Color darkScaffold = Color(0xFF0B0E14);
  static const Color deepDarkBg = Color(0xFF090D16);
  static const Color darkGradientBottom = Color(0xFF080B11);
  static const Color cardDark = Color(0xFF131B2E);
  static const Color storeCardDark = Color(0xFF111827);

  static const LinearGradient screenBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      background,
      darkGradientBottom,
    ],
  );

  static InputDecoration hextechInputDecoration({
    required String hintText,
    String? counterText,
    Color? fillColor,
    Widget? prefixIcon,
    String? suffixText,
    TextStyle? suffixStyle,
    double borderRadius = 12,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  }) {
    return InputDecoration(
      hintText: hintText,
      counterText: counterText,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      prefixIcon: prefixIcon,
      suffixText: suffixText,
      suffixStyle: suffixStyle,
      filled: true,
      fillColor: fillColor ?? Colors.white.withValues(alpha: 0.05),
      contentPadding: contentPadding,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primaryDark,
        surface: surface,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme.copyWith(
          displayLarge: const TextStyle(color: textLight, fontWeight: FontWeight.bold),
          displayMedium: const TextStyle(color: textLight, fontWeight: FontWeight.bold),
          bodyLarge: const TextStyle(color: textLight),
          bodyMedium: const TextStyle(color: textLight),
          bodySmall: const TextStyle(color: textMuted),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: textLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          elevation: 4,
          shadowColor: primary.withValues(alpha: 0.5),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textLight),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textMuted),
      ),
    );
  }
}
