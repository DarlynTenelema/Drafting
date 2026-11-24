import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Modelo Orientado a Objetos que centraliza colores, íconos, etiquetas y resolución
/// de URLs de plataformas de streaming y redes sociales (elimina switches repetidos).
class SocialPlatform {
  final String rawId;

  const SocialPlatform._(this.rawId);

  factory SocialPlatform.fromString(String? raw) {
    return SocialPlatform._((raw ?? '').trim());
  }

  String get normalizedId => rawId.toLowerCase();

  Color get color {
    switch (normalizedId) {
      case 'tiktok':
        return AppTheme.hextechPink;
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'discord':
        return const Color(0xFF5865F2);
      case 'x':
      case 'twitter':
        return AppTheme.hextechCyan;
      case 'twitch':
        return const Color(0xFF9146FF);
      case 'kick':
        return const Color(0xFF53FC18);
      case 'youtube':
        return const Color(0xFFFF0000);
      default:
        return AppTheme.hextechGold;
    }
  }

  /// Color de acento para plataformas de creadores (Twitch, Kick, TikTok por defecto)
  Color get creatorAccentColor {
    switch (normalizedId) {
      case 'twitch':
        return const Color(0xFF9146FF);
      case 'kick':
        return const Color(0xFF53FC18);
      default:
        return AppTheme.hextechPink;
    }
  }

  IconData get icon {
    switch (normalizedId) {
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

  String get label {
    switch (normalizedId) {
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
        return rawId.toUpperCase();
    }
  }

  String get creatorPlatformName {
    switch (normalizedId) {
      case 'twitch':
        return 'Twitch';
      case 'kick':
        return 'Kick';
      default:
        return 'TikTok';
    }
  }

  /// Normaliza una URL externa agregando `https://` si no tiene esquema válido.
  static String normalizeExternalUrl(String rawUrl) {
    String clean = rawUrl.trim();
    if (clean.isEmpty) return '';
    if (!clean.toLowerCase().startsWith('http://') &&
        !clean.toLowerCase().startsWith('https://') &&
        !clean.toLowerCase().startsWith('market://')) {
      clean = 'https://${clean.replaceFirst(RegExp(r'^/+'), '')}';
    }
    return clean;
  }

  /// Resuelve la URL del canal de un creador a partir de su URL o su @handle.
  String resolveCreatorStreamUrl(String rawUrl, String handle) {
    String url = rawUrl.trim();
    final String cleanHandle = handle.trim().replaceFirst(RegExp(r'^@+'), '');
    if (url.isEmpty && cleanHandle.isNotEmpty) {
      switch (normalizedId) {
        case 'twitch':
          return 'https://www.twitch.tv/$cleanHandle';
        case 'kick':
          return 'https://kick.com/$cleanHandle';
        default:
          return 'https://www.tiktok.com/@$cleanHandle';
      }
    }
    if (url.isNotEmpty &&
        !url.toLowerCase().startsWith('http://') &&
        !url.toLowerCase().startsWith('https://')) {
      url = 'https://${url.replaceFirst(RegExp(r'^/+'), '')}';
    }
    return url;
  }
}
