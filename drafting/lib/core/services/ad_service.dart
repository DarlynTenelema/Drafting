import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  AdService._();

  // Test Rewarded Ad Unit ID for Android provided by Google
  static const String _testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  // Production Ad Unit ID (replace with your real AdMob / mediation rewarded unit ID when published)
  static const String _prodRewardedAdUnitId = 'ca-app-pub-6984024121811101/rewarded_main';

  static RewardedAd? _rewardedAd;
  static bool _isAdLoading = false;

  static String get rewardedAdUnitId {
    if (kDebugMode) {
      return _testRewardedAdUnitId;
    }
    // En modo release, usa el ID de producción configurado (o el test si está vacío)
    return _prodRewardedAdUnitId.isNotEmpty ? _prodRewardedAdUnitId : _testRewardedAdUnitId;
  }

  /// Pre-loads a rewarded ad so it is ready immediately when requested
  static void loadRewardedAd() {
    if (_rewardedAd != null || _isAdLoading) return;

    _isAdLoading = true;
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoading = false;
          debugPrint('✅ [AdService] Rewarded Ad cargado exitosamente.');
        },
        onAdFailedToLoad: (LoadAdError error) {
          _rewardedAd = null;
          _isAdLoading = false;
          debugPrint('⚠️ [AdService] Error cargando Rewarded Ad: ${error.message}');
        },
      ),
    );
  }

  /// Shows the rewarded ad and triggers callbacks
  static void showRewardedAd({
    required VoidCallback onUserEarnedReward,
    required Function(String error) onAdFailed,
  }) {
    if (_rewardedAd == null) {
      // Intentar cargar para la próxima vez
      loadRewardedAd();
      onAdFailed('El video aún se está cargando. Por favor inténtalo en unos segundos.');
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd(); // Recargar para la siguiente ocasión
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
        onAdFailed('No se pudo mostrar el video: ${error.message}');
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        onUserEarnedReward();
      },
    );
  }
}
