import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'api_client.dart';

enum IapState {
  initial,
  loading,
  available,
  unavailable,
  error,
}

class IapPurchaseResult {
  final bool success;
  final bool alreadyProcessed;
  final String? message;
  final String? productId;
  final int queriesAdded;
  final bool isSubscription;

  const IapPurchaseResult({
    required this.success,
    this.alreadyProcessed = false,
    this.message,
    this.productId,
    this.queriesAdded = 0,
    this.isSubscription = false,
  });
}

class InAppPurchaseService {
  static final InAppPurchaseService instance = InAppPurchaseService._internal();

  InAppPurchaseService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // IDs oficiales para Google Play Console
  static const String packStarter = 'pack_starter';
  static const String packPlus = 'pack_plus';
  static const String packPro = 'pack_pro';
  static const String packUltra = 'pack_ultra';

  static const String subPlus = 'sub_plus';
  static const String subPro = 'sub_pro';
  static const String subUltra = 'sub_ultra';

  // IDs de Micro-Donaciones para Google Play Console ($0.10 - $0.99)
  static const String donate10 = 'donate_10';
  static const String donate25 = 'donate_25';
  static const String donate49 = 'donate_49';
  static const String donate75 = 'donate_75';
  static const String donate99 = 'donate_99';

  static const Set<String> packIds = {
    packStarter,
    packPlus,
    packPro,
    packUltra,
  };

  static const Set<String> donationIds = {
    donate10,
    donate25,
    donate49,
    donate75,
    donate99,
  };

  static const Set<String> subscriptionIds = {
    subPlus,
    subPro,
    subUltra,
  };

  static const Set<String> allProductIds = {
    ...packIds,
    ...donationIds,
    ...subscriptionIds,
  };

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  final Map<String, ProductDetails> _products = {};
  Map<String, ProductDetails> get products => Map.unmodifiable(_products);

  // Callbacks para comunicar eventos a la UI
  final _purchaseResultController = StreamController<IapPurchaseResult>.broadcast();
  Stream<IapPurchaseResult> get onPurchaseResult => _purchaseResultController.stream;

  final ValueNotifier<bool> isProcessing = ValueNotifier<bool>(false);
  final ValueNotifier<String?> pendingProductId = ValueNotifier<String?>(null);

  bool _isInitialized = false;
  bool _isCleaningUp = false;
  bool _isRecoveringAlreadyOwned = false;
  bool _isManualRestore = false;
  Timer? _processingTimeoutTimer;

  // Protección contra envíos concurrentes o duplicados de la misma compra en una sesión
  final Set<String> _inFlightPurchaseKeys = <String>{};
  final Set<String> _completedPurchaseKeys = <String>{};

  Future<void> initialize() async {
    if (_isInitialized) {
      if (_products.isEmpty) {
        await checkAvailabilityAndLoadProducts();
      }
      unawaited(cleanupPendingPurchasesSilently());
      return;
    }
    _isInitialized = true;

    // Escuchar el stream de compras de Google Play / App Store
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) {
        debugPrint('[IAP] Error en purchaseStream: $error');
        _clearProcessingState();
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          message: 'Error en la conexión con la tienda: $error',
        ));
      },
    );

    await checkAvailabilityAndLoadProducts();
    unawaited(cleanupPendingPurchasesSilently());
  }

  void _clearProcessingState() {
    _processingTimeoutTimer?.cancel();
    _processingTimeoutTimer = null;
    isProcessing.value = false;
    pendingProductId.value = null;
  }

  void _startProcessingTimeout(String productId) {
    _processingTimeoutTimer?.cancel();
    _processingTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (isProcessing.value && pendingProductId.value == productId) {
        isProcessing.value = false;
        pendingProductId.value = null;
      }
    });
  }

  Future<void> checkAvailabilityAndLoadProducts() async {
    try {
      _isAvailable = await _iap.isAvailable();
      debugPrint('[IAP] Tienda disponible: $_isAvailable');

      if (_isAvailable) {
        final ProductDetailsResponse response = await _iap.queryProductDetails(allProductIds);
        if (response.error != null) {
          debugPrint('[IAP] Error cargando productos: ${response.error!.message}');
        } else {
          _products.clear();
          for (final product in response.productDetails) {
            _products[product.id] = product;
            debugPrint('[IAP] Producto cargado: ${product.id} - ${product.title} - ${product.price}');
          }
          if (response.notFoundIDs.isNotEmpty) {
            debugPrint('[IAP] Productos pendientes de aprobación en Google Play: ${response.notFoundIDs}');
          }
        }
      }
    } catch (e) {
      debugPrint('[IAP] Error al inicializar IAP: $e');
      _isAvailable = false;
    }
  }

  /// Limpia silenciosamente compras previas que hayan quedado sin consumir en Google Play
  /// para evitar el bloqueo "Error: Ya compraste este artículo" (ITEM_ALREADY_OWNED)
  Future<void> cleanupPendingPurchasesSilently() async {
    if (_isCleaningUp || !_isAvailable) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    _isCleaningUp = true;
    try {
      final androidAddition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final QueryPurchaseDetailsResponse response = await androidAddition.queryPastPurchases();
      if (response.error != null) {
        debugPrint('[IAP] Error consultando compras previas en Android: ${response.error!.message}');
        return;
      }

      for (final purchase in response.pastPurchases) {
        if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
          await _deliverPurchaseToBackend(purchase, isSilent: true);
        }
      }
    } catch (e) {
      debugPrint('[IAP] Error en limpieza silenciosa de compras: $e');
    } finally {
      _isCleaningUp = false;
    }
  }

  ProductDetails? getProduct(String id) {
    return _products[id];
  }

  String getDisplayPrice(String id, String fallbackPrice) {
    final prod = _products[id];
    if (prod != null && prod.price.isNotEmpty) {
      return prod.price;
    }
    return fallbackPrice;
  }

  /// Inicia la compra de un paquete consumible
  Future<bool> buyPack(String packId) async {
    if (isProcessing.value) return false;

    isProcessing.value = true;
    pendingProductId.value = packId;

    try {
      // Antes de abrir Google Play, asegurar que cualquier compra previa de paquetes
      // que haya quedado atascada sin consumir sea liberada en segundo plano.
      await cleanupPendingPurchasesSilently();

      var product = _products[packId];
      if (product == null) {
        await checkAvailabilityAndLoadProducts();
        product = _products[packId];
      }

      if (!_isAvailable || product == null) {
        _clearProcessingState();
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: packId,
          message: !_isAvailable
              ? 'Google Play Store no está disponible en este momento. Verifica tu conexión e inténtalo de nuevo.'
              : 'El paquete ($packId) no está disponible en Google Play Store en este momento.',
        ));
        return false;
      }

      final purchaseParam = PurchaseParam(productDetails: product);
      // autoConsume: false para consumir explícitamente mediante consumePurchase()
      // inmediatamente después de que el backend valide o confirme la transacción.
      final launched = await _iap.buyConsumable(
        purchaseParam: purchaseParam,
        autoConsume: false,
      );

      if (!launched) {
        _clearProcessingState();
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: packId,
          message: 'No se pudo iniciar la pasarela de compra de Google Play.',
        ));
        return false;
      }

      _startProcessingTimeout(packId);
      return true;
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (_isAlreadyOwnedError(errStr, '')) {
        await _handleAlreadyOwnedError(packId);
        return false;
      }
      _clearProcessingState();
      _purchaseResultController.add(IapPurchaseResult(
        success: false,
        productId: packId,
        message: 'Error al iniciar la compra: $e',
      ));
      return false;
    }
  }

  /// Inicia la suscripción a un plan mensual
  Future<bool> buySubscription(String planId) async {
    if (isProcessing.value) return false;

    isProcessing.value = true;
    pendingProductId.value = planId;

    try {
      var product = _products[planId];
      if (product == null) {
        await checkAvailabilityAndLoadProducts();
        product = _products[planId];
      }

      if (!_isAvailable || product == null) {
        _clearProcessingState();
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: planId,
          message: !_isAvailable
              ? 'Google Play Store no está disponible en este momento. Verifica tu conexión e inténtalo de nuevo.'
              : 'La suscripción ($planId) no está disponible en Google Play Store en este momento.',
        ));
        return false;
      }

      final purchaseParam = PurchaseParam(productDetails: product);
      final launched = await _iap.buyNonConsumable(purchaseParam: purchaseParam);

      if (!launched) {
        _clearProcessingState();
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: planId,
          message: 'No se pudo abrir Google Play para la suscripción.',
        ));
        return false;
      }

      _startProcessingTimeout(planId);
      return true;
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (_isAlreadyOwnedError(errStr, '')) {
        await _handleAlreadyOwnedError(planId);
        return false;
      }
      _clearProcessingState();
      _purchaseResultController.add(IapPurchaseResult(
        success: false,
        productId: planId,
        message: 'Error al iniciar la suscripción: $e',
      ));
      return false;
    }
  }

  /// Restaura compras previas cuando el usuario presiona el botón de Restaurar Compras
  Future<void> restorePurchases() async {
    if (isProcessing.value) return;

    if (!_isAvailable) {
      await checkAvailabilityAndLoadProducts();
      if (!_isAvailable) {
        _purchaseResultController.add(const IapPurchaseResult(
          success: false,
          message: 'Google Play Billing no está disponible en este dispositivo.',
        ));
        return;
      }
    }

    try {
      isProcessing.value = true;
      _isManualRestore = true;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final androidAddition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        final response = await androidAddition.queryPastPurchases();
        if (response.error != null) {
          _clearProcessingState();
          _isManualRestore = false;
          _purchaseResultController.add(IapPurchaseResult(
            success: false,
            message: 'Error al consultar compras en Google Play: ${response.error!.message}',
          ));
          return;
        }

        int newlyCredited = 0;
        for (final purchase in response.pastPurchases) {
          if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
            final credited = await _deliverPurchaseToBackend(purchase, isSilent: true);
            if (credited > 0) {
              newlyCredited += credited;
            }
          }
        }

        _clearProcessingState();
        _isManualRestore = false;

        if (newlyCredited > 0) {
          _purchaseResultController.add(IapPurchaseResult(
            success: true,
            alreadyProcessed: false,
            queriesAdded: newlyCredited,
            message: '¡Se restauraron y acreditaron +$newlyCredited consultas pendientes!',
          ));
        } else {
          _purchaseResultController.add(const IapPurchaseResult(
            success: true,
            alreadyProcessed: true,
            queriesAdded: 0,
            message: 'Tus compras y suscripciones están sincronizadas al día.',
          ));
        }
        return;
      }

      await _iap.restorePurchases();
      Future.delayed(const Duration(seconds: 3), () {
        _clearProcessingState();
        _isManualRestore = false;
      });
    } catch (e) {
      _clearProcessingState();
      _isManualRestore = false;
      _purchaseResultController.add(IapPurchaseResult(
        success: false,
        message: 'Error al restaurar compras: $e',
      ));
    }
  }

  bool _isAlreadyOwnedError(String errMsg, String errCode) {
    final msg = errMsg.toLowerCase();
    final code = errCode.toLowerCase();
    return msg.contains('already') ||
        code.contains('already') ||
        msg.contains('item_already_owned') ||
        code.contains('item_already_owned') ||
        msg.contains('ya compraste') ||
        msg.contains('ya tienes') ||
        msg.contains('7');
  }

  /// Resuelve de forma controlada y sin bucles el error ITEM_ALREADY_OWNED ("Ya compraste este artículo")
  Future<void> _handleAlreadyOwnedError(String? targetProductId) async {
    final productId = (targetProductId != null && targetProductId.isNotEmpty)
        ? targetProductId
        : pendingProductId.value;
    _clearProcessingState();

    if (_isRecoveringAlreadyOwned) return;
    _isRecoveringAlreadyOwned = true;

    try {
      final bool isSub = productId != null && subscriptionIds.contains(productId);

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final androidAddition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        final response = await androidAddition.queryPastPurchases();

        int creditedForTarget = 0;
        bool foundTarget = false;

        if (response.error == null) {
          for (final purchase in response.pastPurchases) {
            if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
              // Sincronizar en silencio y consumir todos los paquetes pendientes para desbloquear Google Play
              final added = await _deliverPurchaseToBackend(purchase, isSilent: true);
              if (purchase.productID == productId) {
                foundTarget = true;
                creditedForTarget += added;
              }
            }
          }
        }

        if (creditedForTarget > 0) {
          // Era una compra real que aún no se había acreditado en el servidor
          _purchaseResultController.add(IapPurchaseResult(
            success: true,
            alreadyProcessed: false,
            productId: productId,
            queriesAdded: creditedForTarget,
            isSubscription: isSub,
            message: isSub
                ? '¡Suscripción sincronizada y activada con éxito!'
                : '¡Paquete pendiente acreditado con éxito!',
          ));
          return;
        }

        if (isSub) {
          _purchaseResultController.add(IapPurchaseResult(
            success: true,
            alreadyProcessed: true,
            productId: productId,
            queriesAdded: 0,
            isSubscription: true,
            message: 'Tu suscripción a este plan ya se encuentra activa en Google Play.',
          ));
        } else {
          _purchaseResultController.add(IapPurchaseResult(
            success: true,
            alreadyProcessed: true,
            productId: productId,
            queriesAdded: 0,
            isSubscription: false,
            message: foundTarget
                ? 'Se liberó una compra pendiente en Google Play. Ya puedes adquirir el paquete nuevamente.'
                : 'El paquete ha sido sincronizado con Google Play. Intenta comprarlo nuevamente.',
          ));
        }
        return;
      }

      // Fallback para iOS
      _purchaseResultController.add(IapPurchaseResult(
        success: false,
        alreadyProcessed: true,
        productId: productId,
        isSubscription: isSub,
        message: isSub
            ? 'Ya tienes esta suscripción activa.'
            : 'Compra previa detectada. Sincroniza tus compras con el botón de restaurar.',
      ));
    } catch (e) {
      debugPrint('[IAP] Error recuperando ITEM_ALREADY_OWNED: $e');
    } finally {
      _isRecoveringAlreadyOwned = false;
    }
  }

  /// Maneja los cambios de estado en el stream de Google Play
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    if (purchaseDetailsList.isEmpty) {
      if (!_isManualRestore) {
        _clearProcessingState();
      }
      return;
    }

    for (final purchase in purchaseDetailsList) {
      debugPrint('[IAP] Estado de compra recibido: ${purchase.productID} -> ${purchase.status}');

      switch (purchase.status) {
        case PurchaseStatus.pending:
          isProcessing.value = true;
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Si viene como restored o de una sincronización en segundo plano, procesarlo sin disparar múltiples modales
          final bool isSilentEvent = _isCleaningUp ||
              _isRecoveringAlreadyOwned ||
              _isManualRestore ||
              (purchase.status == PurchaseStatus.restored && pendingProductId.value != purchase.productID);
          await _deliverPurchaseToBackend(purchase, isSilent: isSilentEvent);
          break;

        case PurchaseStatus.error:
          final targetProd = purchase.productID.isNotEmpty ? purchase.productID : pendingProductId.value;
          final errMsg = purchase.error?.message ?? '';
          final errCode = purchase.error?.code ?? '';
          debugPrint('[IAP] Error en compra ($targetProd): $errCode - $errMsg');

          if (_isAlreadyOwnedError(errMsg, errCode)) {
            await _handleAlreadyOwnedError(targetProd);
            break;
          }

          _clearProcessingState();

          final bool isUserCanceled = errMsg.toLowerCase().contains('cancel') ||
              errCode.toLowerCase().contains('cancel') ||
              errMsg.contains('1');

          if (!isUserCanceled) {
            _purchaseResultController.add(IapPurchaseResult(
              success: false,
              productId: targetProd,
              message: errMsg.isNotEmpty ? errMsg : 'La compra no pudo completarse.',
            ));
          }
          if (purchase.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(purchase);
            } catch (_) {}
          }
          break;

        case PurchaseStatus.canceled:
          _clearProcessingState();
          if (purchase.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(purchase);
            } catch (_) {}
          }
          break;
      }
    }
  }

  String _buildPurchaseKey(PurchaseDetails purchase) {
    final rawId = (purchase.purchaseID ?? '').trim();
    final token = purchase.verificationData.serverVerificationData.trim();
    if (rawId.isNotEmpty) return '${purchase.productID}:$rawId';
    if (token.isNotEmpty) return '${purchase.productID}:$token';
    return '${purchase.productID}:${purchase.transactionDate ?? ''}';
  }

  /// Consume el paquete en Android (para que pueda volver a comprarse sin ITEM_ALREADY_OWNED)
  /// y confirma (acknowledge) la transacción en Google Play / App Store.
  Future<void> _finalizePurchaseInStore(
    PurchaseDetails purchase, {
    required bool isConsumable,
  }) async {
    if (isConsumable && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final androidAddition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        final billingResult = await androidAddition.consumePurchase(purchase);
        debugPrint(
          '[IAP] consumePurchase(${purchase.productID}) -> code=${billingResult.responseCode}, msg=${billingResult.debugMessage}',
        );
      } catch (e) {
        debugPrint('[IAP] Aviso en consumePurchase(${purchase.productID}): $e');
      }
    }

    if (purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
      } catch (e) {
        debugPrint('[IAP] Aviso en completePurchase(${purchase.productID}): $e');
      }
    }
  }

  /// Envía la compra verificada por Google Play al backend, acredita consultas si es nueva,
  /// y consume/finaliza la compra en la tienda para evitar bloqueos o duplicados.
  /// Retorna la cantidad de consultas nuevas acreditadas (0 si ya había sido procesada antes).
  Future<int> _deliverPurchaseToBackend(
    PurchaseDetails purchase, {
    bool isSilent = false,
  }) async {
    final productId = purchase.productID;
    final isSub = subscriptionIds.contains(productId);
    final isConsumable = packIds.contains(productId) || !isSub;
    final purchaseKey = _buildPurchaseKey(purchase);

    // Si esta misma compra ya fue finalizada en esta sesión, asegurar consumo en tienda y salir
    if (_completedPurchaseKeys.contains(purchaseKey)) {
      await _finalizePurchaseInStore(purchase, isConsumable: isConsumable);
      if (!isSilent && pendingProductId.value == productId) {
        _clearProcessingState();
      }
      return 0;
    }

    // Evitar llamadas concurrentes duplicadas al backend para la misma transacción
    if (_inFlightPurchaseKeys.contains(purchaseKey)) {
      return 0;
    }
    _inFlightPurchaseKeys.add(purchaseKey);

    try {
      final rawPurchaseId = (purchase.purchaseID ?? '').trim();
      final token = purchase.verificationData.serverVerificationData.trim();
      final transactionId = rawPurchaseId.isNotEmpty ? rawPurchaseId : token;

      if (transactionId.isEmpty && token.isEmpty) {
        debugPrint('[IAP] Transacción ignorada por no contener orderId ni purchaseToken.');
        if (!isSilent) {
          _clearProcessingState();
          _purchaseResultController.add(IapPurchaseResult(
            success: false,
            productId: productId,
            message: 'No se recibió un comprobante válido de Google Play.',
          ));
        }
        return 0;
      }

      final bool isDonation = donationIds.contains(productId);
      final response = isSub
          ? await ApiClient.post(
              '/api/v1/store/subscribe',
              authenticated: true,
              body: {
                'plan_id': productId,
                'provider': 'google_play',
                'provider_transaction_id': transactionId,
                'purchase_token': token,
                'package_name': 'com.drafting.app',
              },
            )
          : isDonation
              ? await ApiClient.post(
                  '/api/v1/donations/contribute',
                  authenticated: true,
                  body: {
                    'tier_id': productId,
                    'provider': 'google_play',
                    'provider_transaction_id': transactionId,
                    'purchase_token': token,
                  },
                )
              : await ApiClient.post(
                  '/api/v1/store/purchase-pack',
                  authenticated: true,
                  body: {
                    'pack_id': productId,
                    'provider': 'google_play',
                    'provider_transaction_id': transactionId,
                    'purchase_token': token,
                    'package_name': 'com.drafting.app',
                  },
                );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final int queriesAdded = (data['queries_added'] is int) ? data['queries_added'] : 0;
        final bool alreadyProcessed = data['already_processed'] == true || queriesAdded == 0;

        _completedPurchaseKeys.add(purchaseKey);

        // CRÍTICO: Consumir los paquetes en Android (consumePurchase) y completar (acknowledge)
        // tanto si es compra nueva como si ya estaba procesada, para que Google Play NUNCA deje
        // el paquete bloqueado con "Error: Ya compraste este artículo".
        await _finalizePurchaseInStore(purchase, isConsumable: isConsumable);

        if (!isSilent || pendingProductId.value == productId) {
          _clearProcessingState();
        }

        if (!isSilent) {
          _purchaseResultController.add(IapPurchaseResult(
            success: true,
            alreadyProcessed: alreadyProcessed,
            productId: productId,
            message: data['message'] ?? '¡Acreditación completada con éxito!',
            queriesAdded: queriesAdded,
            isSubscription: isSub,
          ));
        } else if (!alreadyProcessed && queriesAdded > 0) {
          // Si durante una limpieza silenciosa se encontró una compra real pagada que no había sido acreditada,
          // notificar una única vez al usuario de sus nuevas consultas.
          _purchaseResultController.add(IapPurchaseResult(
            success: true,
            alreadyProcessed: false,
            productId: productId,
            message: data['message'] ?? '¡Compra pendiente acreditada con éxito!',
            queriesAdded: queriesAdded,
            isSubscription: isSub,
          ));
        }

        return queriesAdded;
      } else if (response.statusCode == 403 || response.statusCode == 409) {
        // Si el servidor indica que el ítem único (ej. Pack Starter) ya fue canjeado antes,
        // consumirlo en Google Play para que no quede atascado en el dispositivo.
        _completedPurchaseKeys.add(purchaseKey);
        await _finalizePurchaseInStore(purchase, isConsumable: isConsumable);

        if (!isSilent) {
          _clearProcessingState();
          _purchaseResultController.add(IapPurchaseResult(
            success: true,
            alreadyProcessed: true,
            productId: productId,
            queriesAdded: 0,
            isSubscription: isSub,
            message: 'Este artículo ya fue acreditado anteriormente en tu cuenta.',
          ));
        }
        return 0;
      } else {
        if (!isSilent) {
          _clearProcessingState();
          _purchaseResultController.add(IapPurchaseResult(
            success: false,
            productId: productId,
            message: 'El servidor no pudo validar la compra (${response.statusCode}): ${response.body}',
          ));
        }
        return 0;
      }
    } catch (e) {
      if (!isSilent) {
        _clearProcessingState();
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: productId,
          message: 'Error al verificar la compra con el servidor: $e',
        ));
      }
      return 0;
    } finally {
      _inFlightPurchaseKeys.remove(purchaseKey);
    }
  }

  void dispose() {
    _processingTimeoutTimer?.cancel();
    _subscription?.cancel();
    _purchaseResultController.close();
  }
}
