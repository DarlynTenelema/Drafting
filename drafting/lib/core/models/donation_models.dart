import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'social_platform.dart';

/// Modelo POO para cada nivel de micro-donación ($0.10 - $0.99).
class DonationTier {
  final String id;
  final String name;
  final double priceUsd;
  final int bonusQueries;
  final String badge;

  const DonationTier({
    required this.id,
    required this.name,
    required this.priceUsd,
    required this.bonusQueries,
    required this.badge,
  });

  factory DonationTier.fromJson(Map<String, dynamic> json) {
    return DonationTier(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      priceUsd: (json['price_usd'] is num) ? (json['price_usd'] as num).toDouble() : 0.10,
      bonusQueries: (json['bonus_queries'] is int) ? json['bonus_queries'] as int : 2,
      badge: (json['badge'] ?? '').toString(),
    );
  }

  String get formattedFallbackPrice => '\$${priceUsd.toStringAsFixed(2)}';

  static const List<DonationTier> defaultTiers = [
    DonationTier(id: 'donate_10', name: 'Chispa Hextech', priceUsd: 0.10, bonusQueries: 2, badge: 'Micro'),
    DonationTier(id: 'donate_25', name: 'Moneda Hextech', priceUsd: 0.25, bonusQueries: 5, badge: 'Popular'),
    DonationTier(id: 'donate_49', name: 'Cristal de Apoyo', priceUsd: 0.49, bonusQueries: 10, badge: 'Streamer'),
    DonationTier(id: 'donate_75', name: 'Orbe Challenger', priceUsd: 0.75, bonusQueries: 15, badge: 'Destacado'),
    DonationTier(id: 'donate_99', name: 'Corona Leyenda', priceUsd: 0.99, bonusQueries: 25, badge: 'Top VIP'),
  ];
}

/// Modelo POO para el perfil de un creador/donador en el Ranking de la Comunidad.
class DonorProfile {
  final int rank;
  final String displayName;
  final String platform;
  final String channelHandle;
  final String channelUrl;
  final String bioMessage;
  final bool isLive;
  final double totalDonatedUsd;

  const DonorProfile({
    this.rank = 1,
    required this.displayName,
    required this.platform,
    required this.channelHandle,
    required this.channelUrl,
    required this.bioMessage,
    required this.isLive,
    this.totalDonatedUsd = 0.0,
  });

  factory DonorProfile.fromJson(Map<String, dynamic> json) {
    return DonorProfile(
      rank: (json['rank'] is int) ? json['rank'] as int : 1,
      displayName: (json['display_name'] ?? 'Donador').toString(),
      platform: (json['platform'] ?? 'tiktok').toString(),
      channelHandle: (json['channel_handle'] ?? '').toString(),
      channelUrl: (json['channel_url'] ?? '').toString(),
      bioMessage: (json['bio_message'] ?? '').toString(),
      isLive: json['is_live'] == true,
      totalDonatedUsd:
          (json['total_donated_usd'] is num) ? (json['total_donated_usd'] as num).toDouble() : 0.0,
    );
  }

  SocialPlatform get socialPlatform => SocialPlatform.fromString(platform);

  bool get hasChannelConfigured => channelUrl.trim().isNotEmpty;

  String get resolvedStreamUrl =>
      socialPlatform.resolveCreatorStreamUrl(channelUrl, channelHandle);

  Color get rankColor {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank == 2) return const Color(0xFFE2E8F0);
    if (rank == 3) return const Color(0xFFCD7F32);
    return AppTheme.hextechCyan;
  }
}
