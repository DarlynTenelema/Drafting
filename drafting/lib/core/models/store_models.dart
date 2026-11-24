import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Modelo POO para un paquete de compra única (consultas o vidas de trivia).
class StorePack {
  final String id;
  final String name;
  final String modelTier;
  final String description;
  final String tag;
  final bool isStarter;
  final int queries;
  final int bonusQueries;
  final int triviaLives;
  final double priceUsd;

  const StorePack({
    required this.id,
    required this.name,
    this.modelTier = '',
    required this.description,
    required this.tag,
    required this.isStarter,
    required this.queries,
    required this.bonusQueries,
    required this.triviaLives,
    required this.priceUsd,
  });

  factory StorePack.fromJson(Map<String, dynamic> json) {
    return StorePack(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      modelTier: (json['model_tier'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      tag: (json['tag'] ?? '').toString(),
      isStarter: json['is_starter'] == true,
      queries: (json['queries'] is int) ? json['queries'] as int : 0,
      bonusQueries: (json['bonus_queries'] is int) ? json['bonus_queries'] as int : 0,
      triviaLives: (json['trivia_lives'] is int) ? json['trivia_lives'] as int : 0,
      priceUsd: (json['price_usd'] is num) ? (json['price_usd'] as num).toDouble() : 0.0,
    );
  }

  bool get isTrivia => triviaLives > 0;
  bool get isFlake => modelTier == 'flake' || id.contains('flake');
  bool get isAureon => modelTier == 'aureon' || id.contains('aureon');
  bool get isPro => isFlake || id == 'pack_pro' || id == 'pro';
  bool get isUltra => isAureon || id == 'pack_ultra' || id == 'ultra';

  String get formattedFallbackPrice => '\$${priceUsd.toStringAsFixed(2)}';

  Color get borderColor {
    if (isTrivia) return AppTheme.hextechCrimson.withValues(alpha: 0.45);
    if (isStarter) return AppTheme.hextechEmerald.withValues(alpha: 0.4);
    if (isPro) return AppTheme.hextechGold.withValues(alpha: 0.5);
    if (isUltra) return AppTheme.hextechPurple.withValues(alpha: 0.5);
    return Colors.white.withValues(alpha: 0.08);
  }

  Color get tagBgColor {
    if (isTrivia) return AppTheme.hextechCrimson.withValues(alpha: 0.2);
    if (isStarter) return AppTheme.hextechEmerald.withValues(alpha: 0.2);
    if (isPro) return AppTheme.hextechGold.withValues(alpha: 0.2);
    if (isUltra) return AppTheme.hextechPurple.withValues(alpha: 0.2);
    return AppTheme.hextechCyan.withValues(alpha: 0.15);
  }

  Color get tagTextColor {
    if (isTrivia) return AppTheme.hextechCrimson;
    if (isStarter) return AppTheme.hextechEmerald;
    if (isPro) return AppTheme.hextechGold;
    if (isUltra) return const Color(0xFFC4B5FD);
    return AppTheme.hextechCyan;
  }

  IconData get icon {
    if (isTrivia) return Icons.favorite_rounded;
    if (isStarter) return Icons.card_giftcard_rounded;
    if (isPro) return Icons.auto_awesome_rounded;
    if (isUltra) return Icons.diamond_rounded;
    return Icons.bolt_rounded;
  }

  Color get buttonBgColor {
    if (isTrivia) return AppTheme.hextechCrimson;
    if (isStarter) return AppTheme.hextechEmerald;
    return AppTheme.hextechCyan;
  }

  Color get buttonFgColor => isTrivia ? Colors.white : Colors.black;
}

/// Modelo POO para un plan de suscripción mensual.
class SubscriptionPlan {
  final String id;
  final String name;
  final String description;
  final String tag;
  final int queriesPerMonth;
  final double priceUsd;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.tag,
    required this.queriesPerMonth,
    required this.priceUsd,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      tag: (json['tag'] ?? '').toString(),
      queriesPerMonth: (json['queries_per_month'] is int) ? json['queries_per_month'] as int : 0,
      priceUsd: (json['price_usd'] is num) ? (json['price_usd'] as num).toDouble() : 0.0,
    );
  }

  bool get isUltra => id == 'sub_ultra' || id == 'ultra';
  bool get isPro => id == 'sub_pro' || id == 'pro';

  IconData get icon {
    if (isUltra) return Icons.workspace_premium_rounded;
    if (isPro) return Icons.military_tech_rounded;
    return Icons.shield_rounded;
  }

  String fallbackPriceWithSuffix(String perMonthSuffix) =>
      '\$${priceUsd.toStringAsFixed(2)}$perMonthSuffix';
}

/// Modelo POO para la respuesta completa del catálogo de la tienda (`/api/v1/store/catalog`).
class StoreCatalog {
  final bool hasPurchasedStarter;
  final bool isSubscribed;
  final String subscriptionPlan;
  final int availableQueries;
  final int classicQueries;
  final int flakeQueries;
  final int aureonQueries;
  final int flakeAdsRemaining;
  final int aureonAdsRemaining;
  final int subscriptionQueries;
  final int purchasedQueries;
  final int dailyTransferredToday;
  final int remainingTransferQuota;
  final bool canTransfer;
  final int giftQueries;
  final String? myReferralCode;
  final List<StorePack> packs;
  final List<SubscriptionPlan> subscriptions;

  const StoreCatalog({
    this.hasPurchasedStarter = false,
    this.isSubscribed = false,
    this.subscriptionPlan = 'none',
    this.availableQueries = 0,
    this.classicQueries = 0,
    this.flakeQueries = 0,
    this.aureonQueries = 0,
    this.flakeAdsRemaining = 2,
    this.aureonAdsRemaining = 1,
    this.subscriptionQueries = 0,
    this.purchasedQueries = 0,
    this.dailyTransferredToday = 0,
    this.remainingTransferQuota = 10,
    this.canTransfer = false,
    this.giftQueries = 0,
    this.myReferralCode,
    this.packs = const [],
    this.subscriptions = const [],
  });

  factory StoreCatalog.fromJson(Map<String, dynamic> data) {
    final rawPacks = (data['packs'] is List) ? data['packs'] as List<dynamic> : const [];
    final rawSubs =
        (data['subscriptions'] is List) ? data['subscriptions'] as List<dynamic> : const [];

    return StoreCatalog(
      hasPurchasedStarter: data['has_purchased_starter'] == true,
      isSubscribed: data['is_subscribed'] == true,
      subscriptionPlan: (data['subscription_plan'] ?? 'none').toString(),
      availableQueries: (data['available_queries'] is int) ? data['available_queries'] as int : 0,
      classicQueries: (data['classic_queries'] is int) ? data['classic_queries'] as int : 0,
      flakeQueries: (data['flake_queries'] is int) ? data['flake_queries'] as int : 0,
      aureonQueries: (data['aureon_queries'] is int) ? data['aureon_queries'] as int : 0,
      flakeAdsRemaining:
          (data['flake_ads_remaining'] is int) ? data['flake_ads_remaining'] as int : 2,
      aureonAdsRemaining:
          (data['aureon_ads_remaining'] is int) ? data['aureon_ads_remaining'] as int : 1,
      subscriptionQueries:
          (data['subscription_queries'] is int) ? data['subscription_queries'] as int : 0,
      purchasedQueries:
          (data['purchased_queries'] is int) ? data['purchased_queries'] as int : 0,
      dailyTransferredToday:
          (data['daily_transferred_today'] is int) ? data['daily_transferred_today'] as int : 0,
      remainingTransferQuota:
          (data['remaining_transfer_quota'] is int) ? data['remaining_transfer_quota'] as int : 10,
      canTransfer: data['can_transfer'] == true,
      giftQueries: (data['gift_queries'] is int) ? data['gift_queries'] as int : 0,
      myReferralCode: data['referral_code']?.toString(),
      packs: rawPacks
          .whereType<Map<String, dynamic>>()
          .map(StorePack.fromJson)
          .toList(),
      subscriptions: rawSubs
          .whereType<Map<String, dynamic>>()
          .map(SubscriptionPlan.fromJson)
          .toList(),
    );
  }

  List<StorePack> get queryPacks => packs.where((p) => !p.isTrivia).toList();
  List<StorePack> get triviaPacks => packs.where((p) => p.isTrivia).toList();
}
