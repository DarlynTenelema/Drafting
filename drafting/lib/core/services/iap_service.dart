import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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
  final String? message;
  final String? productId;
  final int queriesAdded;
  final bool isSubscription;

  const IapPurchaseResult({
    required this.success,
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

  static const Set<String> packIds = {
    packStarter,
    packPlus,
    packPro,
    packUltra,
  };

  static const Set<String> subscriptionIds = {
    subPlus,
    subPro,
    subUltra,
  };

  static const Set<String> allProductIds = {
    ...packIds,
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

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Escuchar el stream de compras
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) {
        debugPrint('[IAP] Error en purchaseStream: $error');
        isProcessing.value = false;
        pendingProductId.value = null;
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          message: 'Error en la conexión con la tienda: $error',
        ));
      },
    );

    await checkAvailabilityAndLoadProducts();
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
      final product = _products[packId];
      if (product == null) {
        // Si no está registrado en Google Play aún (ej: en desarrollo/pruebas locales),
        // o si Play Store no está disponible en este entorno:
        if (!_isAvailable || kDebugMode) {
          debugPrint('[IAP] Producto $packId no encontrado en Play Store. Utilizando verificación directa backend.');
          return await _simulateBackendPurchase(packId: packId, isSubscription: false);
        }

        isProcessing.value = false;
        pendingProductId.value = null;
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: packId,
          message: 'El producto aún no está sincronizado en Google Play Store. Verifica el estado en Play Console.',
        ));
        return false;
      }

      final purchaseParam = PurchaseParam(productDetails: product);
      // autoConsume: false para consumir sólo después de que nuestro backend acredite las consultas
      final launched = await _iap.buyConsumable(
        purchaseParam: purchaseParam,
        autoConsume: false,
      );

      if (!launched) {
        isProcessing.value = false;
        pendingProductId.value = null;
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: packId,
          message: 'No se pudo iniciar la pasarela de compra de Google Play.',
        ));
        return false;
      }

      return true;
    } catch (e) {
      isProcessing.value = false;
      pendingProductId.value = null;
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
      final product = _products[planId];
      if (product == null) {
        if (!_isAvailable || kDebugMode) {
          debugPrint('[IAP] Suscripción $planId no encontrada en Play Store. Utilizando verificación directa backend.');
          return await _simulateBackendPurchase(planId: planId, isSubscription: true);
        }

        isProcessing.value = false;
        pendingProductId.value = null;
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: planId,
          message: 'La suscripción aún no está activa en Google Play Store. Verifica el estado en Play Console.',
        ));
        return false;
      }

      final purchaseParam = PurchaseParam(productDetails: product);
      final launched = await _iap.buyNonConsumable(purchaseParam: purchaseParam);

      if (!launched) {
        isProcessing.value = false;
        pendingProductId.value = null;
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: planId,
          message: 'No se pudo abrir Google Play para la suscripción.',
        ));
        return false;
      }

      return true;
    } catch (e) {
      isProcessing.value = false;
      pendingProductId.value = null;
      _purchaseResultController.add(IapPurchaseResult(
        success: false,
        productId: planId,
        message: 'Error al iniciar la suscripción: $e',
      ));
      return false;
    }
  }

  /// Restaura compras previas (requerido para suscripciones)
  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      _purchaseResultController.add(const IapPurchaseResult(
        success: false,
        message: 'Google Play Billing no está disponible en este dispositivo.',
      ));
      return;
    }

    try {
      isProcessing.value = true;
      await _iap.restorePurchases();
    } catch (e) {
      isProcessing.value = false;
      _purchaseResultController.add(IapPurchaseResult(
        success: false,
        message: 'Error al restaurar compras: $e',
      ));
    }
  }

  /// Maneja los cambios de estado en la pasarela de Google Play
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchase in purchaseDetailsList) {
      debugPrint('[IAP] Estado de compra recibido: ${purchase.productID} -> ${purchase.status}');

      switch (purchase.status) {
        case PurchaseStatus.pending:
          isProcessing.value = true;
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _deliverPurchaseToBackend(purchase);
          break;

        case PurchaseStatus.error:
          isProcessing.value = false;
          pendingProductId.value = null;
          debugPrint('[IAP] Error en compra: ${purchase.error}');
          _purchaseResultController.add(IapPurchaseResult(
            success: false,
            productId: purchase.productID,
            message: purchase.error?.message ?? 'La compra fue cancelada o falló.',
          ));
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          break;

        case PurchaseStatus.canceled:
          isProcessing.value = false;
          pendingProductId.value = null;
          _purchaseResultController.add(IapPurchaseResult(
            success: false,
            productId: purchase.productID,
            message: 'Compra cancelada por el usuario.',
          ));
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          break;
      }
    }
  }

  /// Envía la compra verificada por Google Play al backend y acredita las consultas
  Future<void> _deliverPurchaseToBackend(PurchaseDetails purchase) async {
    final productId = purchase.productID;
    final isSub = subscriptionIds.contains(productId);

    try {
      final transactionId = purchase.purchaseID ?? purchase.verificationData.serverVerificationData;
      final token = purchase.verificationData.serverVerificationData;

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

        // ¡MUY IMPORTANTE!: Consumir o finalizar la compra en Google Play para que no la cancele en 3 días
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }

        isProcessing.value = false;
        pendingProductId.value = null;

        _purchaseResultController.add(IapPurchaseResult(
          success: true,
          productId: productId,
          message: data['message'] ?? '¡Acreditación completada con éxito!',
          queriesAdded: data['queries_added'] ?? data['subscription_queries'] ?? 0,
          isSubscription: isSub,
        ));
      } else {
        isProcessing.value = false;
        pendingProductId.value = null;

        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: productId,
          message: 'El servidor no pudo validar la compra (${response.statusCode}): ${response.body}',
        ));
      }
    } catch (e) {
      isProcessing.value = false;
      pendingProductId.value = null;

      _purchaseResultController.add(IapPurchaseResult(
        success: false,
        productId: productId,
        message: 'Error al enviar compra al servidor: $e',
      ));
    }
  }

  /// Modo fallback/desarrollo cuando los productos aún no están publicados o se prueba en emulador
  Future<bool> _simulateBackendPurchase({
    String? packId,
    String? planId,
    required bool isSubscription,
  }) async {
    try {
      final id = isSubscription ? planId! : packId!;
      final txId = 'test_gp_${DateTime.now().millisecondsSinceEpoch}';

      final response = isSubscription
          ? await ApiClient.post(
              '/api/v1/store/subscribe',
              authenticated: true,
              body: {
                'plan_id': id,
                'provider': 'google_play_sandbox',
                'provider_transaction_id': txId,
                'package_name': 'com.drafting.app',
              },
            )
          : await ApiClient.post(
              '/api/v1/store/purchase-pack',
              authenticated: true,
              body: {
                'pack_id': id,
                'provider': 'google_play_sandbox',
                'provider_transaction_id': txId,
                'package_name': 'com.drafting.app',
              },
            );

      isProcessing.value = false;
      pendingProductId.value = null;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _purchaseResultController.add(IapPurchaseResult(
          success: true,
          productId: id,
          message: data['message'] ?? '¡Acreditación completada con éxito!',
          queriesAdded: data['queries_added'] ?? data['subscription_queries'] ?? 0,
          isSubscription: isSubscription,
        ));
        return true;
      } else {
        _purchaseResultController.add(IapPurchaseResult(
          success: false,
          productId: id,
          message: response.body.isNotEmpty ? response.body : 'Error en la compra.',
        ));
        return false;
      }
    } catch (e) {
      isProcessing.value = false;
      pendingProductId.value = null;
      _purchaseResultController.add(IapPurchaseResult(
        success: false,
        productId: isSubscription ? planId : packId,
        message: 'Error de conexión: $e',
      ));
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _purchaseResultController.close();
  }
}
