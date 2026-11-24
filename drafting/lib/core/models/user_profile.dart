import 'package:shared_preferences/shared_preferences.dart';

/// Modelo POO que encapsula el saldo y desglose de consultas del usuario,
/// su lógica de descuento por prioridad y su persistencia en caché local.
class QueryBalance {
  int available;
  int daily;
  int bonus;
  int ad;
  int purchased;
  int subscription;

  // Billeteras independientes por modelo (Classic, Flake 1.0, Aureon 1.0)
  int classicQueries;
  int classicDaily;
  int classicAd;
  int classicPurchased;

  int flakeQueries;
  int flakeAd;
  int flakePurchased;
  int flakeAdsRemaining;

  int aureonQueries;
  int aureonAd;
  int aureonPurchased;
  int aureonAdsRemaining;

  QueryBalance({
    this.available = 3,
    this.daily = 3,
    this.bonus = 0,
    this.ad = 0,
    this.purchased = 0,
    this.subscription = 0,
    this.classicQueries = 3,
    this.classicDaily = 3,
    this.classicAd = 0,
    this.classicPurchased = 0,
    this.flakeQueries = 0,
    this.flakeAd = 0,
    this.flakePurchased = 0,
    this.flakeAdsRemaining = 2,
    this.aureonQueries = 0,
    this.aureonAd = 0,
    this.aureonPurchased = 0,
    this.aureonAdsRemaining = 1,
  });

  int queriesForModel(String modelTier) {
    switch (modelTier.toLowerCase()) {
      case 'flake':
        return flakeQueries;
      case 'aureon':
        return aureonQueries;
      default:
        return classicQueries;
    }
  }

  bool isAdOnCooldown(String modelTier) {
    switch (modelTier.toLowerCase()) {
      case 'flake':
        return flakeAdsRemaining <= 0;
      case 'aureon':
        return aureonAdsRemaining <= 0;
      default:
        return false;
    }
  }

  /// Descuenta 1 consulta estrictamente del modelo seleccionado
  void decrementForModel(String modelTier) {
    switch (modelTier.toLowerCase()) {
      case 'flake':
        if (flakeQueries > 0) flakeQueries--;
        if (flakeAd > 0) {
          flakeAd--;
        } else if (flakePurchased > 0) {
          flakePurchased--;
        }
        break;
      case 'aureon':
        if (aureonQueries > 0) aureonQueries--;
        if (aureonAd > 0) {
          aureonAd--;
        } else if (aureonPurchased > 0) {
          aureonPurchased--;
        }
        break;
      default:
        if (classicQueries > 0) classicQueries--;
        if (classicDaily > 0) {
          classicDaily--;
        } else if (classicAd > 0) {
          classicAd--;
        } else if (classicPurchased > 0) {
          classicPurchased--;
        }
        break;
    }
    available = classicQueries + flakeQueries + aureonQueries;
  }

  /// Compatibilidad legacy: descuenta del modelo Classic
  void decrementOne() => decrementForModel('classic');

  /// Actualiza los contadores con el payload parcial o completo del servidor.
  void updateFromServerMap(Map<String, dynamic> data, {int? fallbackAddedAdQueries}) {
    if (data['available_queries'] is int) {
      available = data['available_queries'] as int;
    } else if (fallbackAddedAdQueries != null) {
      available += fallbackAddedAdQueries;
    }

    if (data['daily_queries'] is int) daily = data['daily_queries'] as int;
    if (data['bonus_queries'] is int) bonus = data['bonus_queries'] as int;
    if (data['ad_queries'] is int) {
      ad = data['ad_queries'] as int;
    } else if (fallbackAddedAdQueries != null) {
      ad += fallbackAddedAdQueries;
    }
    if (data['purchased_queries'] is int) purchased = data['purchased_queries'] as int;
    if (data['subscription_queries'] is int) subscription = data['subscription_queries'] as int;

    if (data['classic_queries'] is int) classicQueries = data['classic_queries'] as int;
    if (data['classic_daily'] is int) classicDaily = data['classic_daily'] as int;
    if (data['classic_ad'] is int) classicAd = data['classic_ad'] as int;
    if (data['classic_purchased'] is int) classicPurchased = data['classic_purchased'] as int;

    if (data['flake_queries'] is int) flakeQueries = data['flake_queries'] as int;
    if (data['flake_ad'] is int) flakeAd = data['flake_ad'] as int;
    if (data['flake_purchased'] is int) flakePurchased = data['flake_purchased'] as int;
    if (data['flake_ads_remaining'] is int) flakeAdsRemaining = data['flake_ads_remaining'] as int;

    if (data['aureon_queries'] is int) aureonQueries = data['aureon_queries'] as int;
    if (data['aureon_ad'] is int) aureonAd = data['aureon_ad'] as int;
    if (data['aureon_purchased'] is int) aureonPurchased = data['aureon_purchased'] as int;
    if (data['aureon_ads_remaining'] is int) aureonAdsRemaining = data['aureon_ads_remaining'] as int;
  }

  void loadFromPrefs(SharedPreferences prefs) {
    available = prefs.getInt('available_queries') ?? 3;
    daily = prefs.getInt('daily_queries') ?? 3;
    bonus = prefs.getInt('bonus_queries') ?? 0;
    ad = prefs.getInt('ad_queries') ?? 0;
    purchased = prefs.getInt('purchased_queries') ?? 0;
    subscription = prefs.getInt('subscription_queries') ?? 0;

    classicQueries = prefs.getInt('classic_queries') ?? available;
    classicDaily = prefs.getInt('classic_daily') ?? daily;
    classicAd = prefs.getInt('classic_ad') ?? ad;
    classicPurchased = prefs.getInt('classic_purchased') ?? purchased;

    flakeQueries = prefs.getInt('flake_queries') ?? 0;
    flakeAd = prefs.getInt('flake_ad') ?? 0;
    flakePurchased = prefs.getInt('flake_purchased') ?? 0;
    flakeAdsRemaining = prefs.getInt('flake_ads_remaining') ?? 2;

    aureonQueries = prefs.getInt('aureon_queries') ?? 0;
    aureonAd = prefs.getInt('aureon_ad') ?? 0;
    aureonPurchased = prefs.getInt('aureon_purchased') ?? 0;
    aureonAdsRemaining = prefs.getInt('aureon_ads_remaining') ?? 1;
  }

  Future<void> saveToPrefs(SharedPreferences prefs) async {
    await prefs.setInt('available_queries', available);
    await prefs.setInt('daily_queries', daily);
    await prefs.setInt('bonus_queries', bonus);
    await prefs.setInt('ad_queries', ad);
    await prefs.setInt('purchased_queries', purchased);
    await prefs.setInt('subscription_queries', subscription);

    await prefs.setInt('classic_queries', classicQueries);
    await prefs.setInt('classic_daily', classicDaily);
    await prefs.setInt('classic_ad', classicAd);
    await prefs.setInt('classic_purchased', classicPurchased);

    await prefs.setInt('flake_queries', flakeQueries);
    await prefs.setInt('flake_ad', flakeAd);
    await prefs.setInt('flake_purchased', flakePurchased);
    await prefs.setInt('flake_ads_remaining', flakeAdsRemaining);

    await prefs.setInt('aureon_queries', aureonQueries);
    await prefs.setInt('aureon_ad', aureonAd);
    await prefs.setInt('aureon_purchased', aureonPurchased);
    await prefs.setInt('aureon_ads_remaining', aureonAdsRemaining);
  }
}

/// Modelo POO que encapsula el perfil completo del jugador, suscripción y referidos.
class UserProfile {
  String? userName;
  String? userEmail;
  String? userPhotoUrl;
  String? referralCode;
  int referralCount;
  int referralRewardsClaimed;
  bool hasRedeemedReferral;
  String subscriptionPlan;
  bool isSubscribed;
  final QueryBalance queries;

  UserProfile({
    this.userName,
    this.userEmail,
    this.userPhotoUrl,
    this.referralCode,
    this.referralCount = 0,
    this.referralRewardsClaimed = 0,
    this.hasRedeemedReferral = false,
    this.subscriptionPlan = 'none',
    this.isSubscribed = false,
    QueryBalance? queries,
  }) : queries = queries ?? QueryBalance();

  void loadFromPrefs(SharedPreferences prefs) {
    queries.loadFromPrefs(prefs);
    subscriptionPlan = prefs.getString('subscription_plan') ?? 'none';
    isSubscribed = prefs.getBool('is_subscribed') ?? false;
    userEmail = prefs.getString('user_email');
  }

  Future<void> updateFromMeResponse(
    Map<String, dynamic> data,
    SharedPreferences prefs,
  ) async {
    userName = (data['username'] ?? 'Jugador').toString();
    userEmail = data['email']?.toString();
    userPhotoUrl = data['profile_pic']?.toString();
    if (userEmail != null) {
      await prefs.setString('user_email', userEmail!);
    }

    referralCode = data['referral_code']?.toString();
    referralCount = (data['referral_count'] is int) ? data['referral_count'] as int : 0;
    referralRewardsClaimed =
        (data['referral_rewards_claimed'] is int) ? data['referral_rewards_claimed'] as int : 0;
    hasRedeemedReferral = data['has_redeemed_referral'] == true;

    queries.updateFromServerMap(data);

    if (data['subscription_plan'] is String) {
      subscriptionPlan = data['subscription_plan'] as String;
      await prefs.setString('subscription_plan', subscriptionPlan);
    }
    isSubscribed = data['is_premium'] == true || data['is_subscribed'] == true;
    await prefs.setBool('is_subscribed', isSubscribed);
    await queries.saveToPrefs(prefs);
  }
}
