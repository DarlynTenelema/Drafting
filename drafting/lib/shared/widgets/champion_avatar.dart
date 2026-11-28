import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// Avatar local de campeones de Wild Rift cargado desde `assets/champions/{slug}.webp`.
/// Funciona 100% offline, con carga instantánea y fallback limpio si el nombre no coincide.
class ChampionAvatar extends StatelessWidget {
  final String championName;
  final double size;
  final Color borderColor;
  final double borderWidth;
  final bool isCircle;

  const ChampionAvatar({
    super.key,
    required this.championName,
    this.size = 48,
    this.borderColor = AppTheme.hextechCyan,
    this.borderWidth = 1.8,
    this.isCircle = true,
  });

  /// Normaliza el nombre del campeón al mismo slug generado en `assets/champions/`.
  static String toSlug(String name) {
    var s = name.toLowerCase().trim();
    const accents = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'ã': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    accents.forEach((k, v) => s = s.replaceAll(k, v));
    s = s
        .replaceAll("'", '')
        .replaceAll('’', '')
        .replaceAll('.', '')
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('_', '');
    return s;
  }

  static String assetPath(String name) => 'assets/champions/${toSlug(name)}.webp';

  @override
  Widget build(BuildContext context) {
    final radius = isCircle ? size / 2 : size * 0.22;
    final initial = championName.trim().isNotEmpty
        ? championName.trim().substring(0, 1).toUpperCase()
        : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.28),
            blurRadius: 10,
            spreadRadius: 0.5,
          ),
        ],
        color: AppTheme.surface,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          assetPath(championName),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              initial,
              style: GoogleFonts.outfit(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
