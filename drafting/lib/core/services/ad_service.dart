import 'package:flutter/foundation.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

class AdService {
  AdService._();

  /// Tu App Key oficial de Appodeal para Drafting (com.drafting.app)
  static const String _prodAppKey = 'cf548729025e1d9f171009314a857329861b064c46f7ca20';
  static String appKey = _prodAppKey;

  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  /// Callbacks activos para la sesión actual del anuncio bonificado
  static VoidCallback? _onUserEarnedRewardCallback;
  static Function(String error)? _onAdFailedCallback;

  /// Inicializa el SDK de mediación Appodeal
  static Future<void> initialize({String? customAppKey}) async {
    if (_isInitialized) return;

    if (customAppKey != null && customAppKey.isNotEmpty) {
      appKey = customAppKey;
    }

    try {
      // Modo de pruebas automático en desarrollo para no arriesgar la cuenta
      if (kDebugMode) {
        await Appodeal.setTesting(true);
        Appodeal.setLogLevel(Appodeal.LogLevelVerbose);
        debugPrint('🛠️ [Appodeal] Modo de pruebas (Testing) activado.');
      } else {
        await Appodeal.setTesting(false);
        Appodeal.setLogLevel(Appodeal.LogLevelNone);
      }

      // Habilitar caché automático de videos recompensados
      Appodeal.setAutoCache(AppodealAdType.RewardedVideo, true);

      // Registrar los escuchadores globales de eventos para Rewarded Video
      _setupCallbacks();

      // Inicializar el SDK con soporte para Rewarded Video
      Appodeal.initialize(
        appKey: appKey,
        adTypes: [
          AppodealAdType.RewardedVideo,
        ],
        onInitializationFinished: (errors) {
          _isInitialized = true;
          if (errors != null && errors.isNotEmpty) {
            debugPrint('⚠️ [Appodeal] Inicializado con avisos: $errors');
          } else {
            debugPrint('✅ [Appodeal] Inicializado con éxito.');
          }
          // Precargar el primer video de recompensa
          loadRewardedAd();
        },
      );
    } catch (e) {
      debugPrint('🔴 [Appodeal] Error durante la inicialización: $e');
    }
  }

  /// Configura los eventos nativos del ciclo de vida del video bonificado
  static void _setupCallbacks() {
    Appodeal.setRewardedVideoCallbacks(
      onRewardedVideoLoaded: (bool isPrecache) {
        debugPrint('✅ [Appodeal] Video recompensado cargado y listo (isPrecache: $isPrecache)');
      },
      onRewardedVideoFailedToLoad: () {
        debugPrint('⚠️ [Appodeal] Falló la carga del video recompensado.');
      },
      onRewardedVideoShown: () {
        debugPrint('🎬 [Appodeal] Video recompensado en pantalla.');
      },
      onRewardedVideoShowFailed: () {
        debugPrint('🔴 [Appodeal] Error al mostrar el video recompensado.');
        _onAdFailedCallback?.call('No se pudo reproducir el anuncio. Inténtalo en unos segundos.');
        _clearActiveCallbacks();
      },
      onRewardedVideoFinished: (double amount, String reward) {
        debugPrint('🎁 [Appodeal] Usuario completó el video. Acreditando recompensa ($amount $reward).');
        _onUserEarnedRewardCallback?.call();
      },
      onRewardedVideoClosed: (bool isFinished) {
        debugPrint('🚪 [Appodeal] Video cerrado por el usuario (completado: $isFinished).');
        _clearActiveCallbacks();
        // Cargar inmediatamente el siguiente video para tenerlo listo
        loadRewardedAd();
      },
      onRewardedVideoClicked: () {
        debugPrint('👆 [Appodeal] Clic en el anuncio.');
      },
    );
  }

  static void _clearActiveCallbacks() {
    _onUserEarnedRewardCallback = null;
    _onAdFailedCallback = null;
  }

  /// Precarga un video recompensado para que esté listo al instante
  static void loadRewardedAd() {
    try {
      Appodeal.cache(AppodealAdType.RewardedVideo);
    } catch (e) {
      debugPrint('⚠️ [Appodeal] Error precargando anuncio: $e');
    }
  }

  /// Verifica si hay un video disponible para reproducir
  static Future<bool> isAdReady() async {
    try {
      return await Appodeal.isLoaded(AppodealAdType.RewardedVideo);
    } catch (_) {
      return false;
    }
  }

  /// Muestra el video bonificado y ejecuta los callbacks de recompensa o fallo
  static Future<void> showRewardedAd({
    required VoidCallback onUserEarnedReward,
    required Function(String error) onAdFailed,
  }) async {
    _onUserEarnedRewardCallback = onUserEarnedReward;
    _onAdFailedCallback = onAdFailed;

    try {
      final isReady = await Appodeal.isLoaded(AppodealAdType.RewardedVideo);

      if (!isReady) {
        loadRewardedAd();
        onAdFailed('El video aún se está preparando en la subasta. Por favor intenta en unos segundos.');
        _clearActiveCallbacks();
        return;
      }

      final shown = await Appodeal.show(AppodealAdType.RewardedVideo);
      if (!shown) {
        loadRewardedAd();
        onAdFailed('No se pudo abrir el anuncio en este momento. Inténtalo de nuevo.');
        _clearActiveCallbacks();
      }
    } catch (e) {
      loadRewardedAd();
      onAdFailed('Error al iniciar el anuncio: $e');
      _clearActiveCallbacks();
    }
  }
}
