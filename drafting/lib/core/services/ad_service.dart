import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Servicio de monetización y anuncios bonificados mediante Google AdMob oficial.
class AdService {
  AdService._();

  /// ID oficial de prueba de Google para Anuncios Recompensados en Android.
  /// Garantiza tasa de llenado (fill rate) del 100% en modo debug sin riesgo para la cuenta.
  static const String _testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  /// ID de producción de tu unidad de anuncios bonificados creada en Google AdMob.
  /// Formato esperado: ca-app-pub-6984024121811101/XXXXXXXXXX
  static const String _defaultProdRewardedAdUnitId = 'ca-app-pub-6984024121811101/4356757298';

  static String _customAdUnitId = const String.fromEnvironment(
    'ADMOB_REWARDED_AD_UNIT_ID',
    defaultValue: _defaultProdRewardedAdUnitId,
  );

  /// Permite configurar o actualizar el ID de la unidad en tiempo de ejecución
  static set rewardedAdUnitId(String id) {
    if (id.trim().isNotEmpty) {
      _customAdUnitId = id.trim();
    }
  }

  /// Retorna el ID correspondiente según el entorno (Pruebas en Debug / Producción en Release)
  static String get rewardedAdUnitId {
    if (kDebugMode) {
      return _testRewardedAdUnitId;
    }
    return _customAdUnitId;
  }

  static bool _isInitialized = false;
  static bool _isInitializing = false;
  static bool get isInitialized => _isInitialized;

  static RewardedAd? _rewardedAd;
  static bool _isLoadingAd = false;
  static int _retryAttempt = 0;

  /// Inicializa el SDK nativo de Google Mobile Ads
  static Future<void> initialize({String? adUnitId}) async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;

    if (adUnitId != null && adUnitId.isNotEmpty) {
      _customAdUnitId = adUnitId;
    }

    try {
      debugPrint('🚀 [AdMob] Inicializando Google Mobile Ads SDK...');
      final initStatus = await MobileAds.instance.initialize();
      _isInitialized = true;
      _isInitializing = false;

      debugPrint('✅ [AdMob] SDK inicializado con éxito: ${initStatus.adapterStatuses}');

      // Precargar de inmediato el primer video bonificado
      loadRewardedAd();
    } catch (e) {
      _isInitializing = false;
      debugPrint('🔴 [AdMob] Error durante la inicialización: $e');
    }
  }

  /// Precarga un anuncio bonificado en memoria para que se reproduzca al instante
  static void loadRewardedAd() {
    if (_rewardedAd != null || _isLoadingAd) {
      return;
    }

    if (!_isInitialized) {
      initialize();
      return;
    }

    _isLoadingAd = true;
    final unitId = rewardedAdUnitId;
    debugPrint('⏳ [AdMob] Cargando video recompensado con unidad: $unitId (Debug: $kDebugMode)');

    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          debugPrint('✅ [AdMob] Video recompensado cargado y listo para mostrarse.');
          _rewardedAd = ad;
          _isLoadingAd = false;
          _retryAttempt = 0;
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('⚠️ [AdMob] Falló la carga del video recompensado: $error (código: ${error.code})');
          _rewardedAd = null;
          _isLoadingAd = false;

          // Reintento con retraso exponencial progresivo (máx 3 reintentos)
          _retryAttempt++;
          if (_retryAttempt <= 3) {
            final delaySeconds = _retryAttempt * 5;
            debugPrint('🔄 [AdMob] Reintentando carga de anuncio en $delaySeconds segundos...');
            Future.delayed(Duration(seconds: delaySeconds), () {
              loadRewardedAd();
            });
          }
        },
      ),
    );
  }

  /// Verifica si hay un video listo para reproducirse
  static Future<bool> isAdReady() async {
    return _rewardedAd != null;
  }

  /// Muestra el video bonificado y ejecuta los callbacks de recompensa o fallo
  static Future<void> showRewardedAd({
    required VoidCallback onUserEarnedReward,
    required Function(String error) onAdFailed,
  }) async {
    if (_rewardedAd == null) {
      loadRewardedAd();
      onAdFailed('El video aún se está preparando. Por favor intenta de nuevo en unos segundos.');
      return;
    }

    bool rewardEarned = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedAd ad) {
        debugPrint('🎬 [AdMob] Video recompensado en pantalla completa.');
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        debugPrint('🚪 [AdMob] Video cerrado por el usuario.');
        ad.dispose();
        _rewardedAd = null;
        // Precargar inmediatamente el siguiente video para el usuario
        loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        debugPrint('🔴 [AdMob] Error al mostrar video en pantalla completa: $error');
        ad.dispose();
        _rewardedAd = null;
        onAdFailed('No se pudo reproducir el anuncio. Por favor inténtalo en unos segundos.');
        loadRewardedAd();
      },
    );

    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          debugPrint('🎁 [AdMob] Usuario completó el video. Acreditando recompensa (+${reward.amount} ${reward.type}).');
          if (!rewardEarned) {
            rewardEarned = true;
            onUserEarnedReward();
          }
        },
      );
    } catch (e) {
      debugPrint('🔴 [AdMob] Excepción al mostrar anuncio: $e');
      _rewardedAd?.dispose();
      _rewardedAd = null;
      onAdFailed('Error al abrir el anuncio: $e');
      loadRewardedAd();
    }
  }
}
