import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/services/api_client.dart';
import '../core/services/subscription_service.dart';
import '../theme/app_theme.dart';

class PaymentScreen extends StatefulWidget {
  final String sessionToken;
  const PaymentScreen({super.key, required this.sessionToken});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  List<ProductDetails> _products = [];
  SubscriptionStatus? _subscriptionStatus;
  bool _isAvailable = false;
  bool _loading = true;
  bool _verifying = false;
  final Set<String> _processedPurchaseKeys = {};

  static const Set<String> _kProductIds = {
    'sub_micro_24h',
    'sub_micro_72h',
    'sub_micro_120h',
    'sub_medium_30d',
    'sub_medium_90d',
    'sub_medium_150d',
    'sub_max_180d',
    'sub_max_240d',
    'sub_max_365d',
  };

  @override
  void initState() {
    super.initState();
    _subscription = _inAppPurchase.purchaseStream.listen(
      _listenToPurchaseUpdated,
      onDone: () => _subscription.cancel(),
      onError: (_) => _showMessage('Error en el flujo de compra.', isError: true),
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadSubscriptionStatus(),
      _initStoreInfo(),
    ]);
  }

  Future<void> _loadSubscriptionStatus() async {
    try {
      final status = await SubscriptionService.getStatus(sessionToken: widget.sessionToken);
      if (mounted) {
        setState(() => _subscriptionStatus = status);
      }
    } catch (_) {
      // Non-blocking: store may still work even if status fails.
    }
  }

  Future<void> _initStoreInfo() async {
    final bool isAvailable = await _inAppPurchase.isAvailable();
    if (!isAvailable) {
      if (mounted) {
        setState(() {
          _isAvailable = false;
          _products = [];
          _loading = false;
        });
      }
      return;
    }

    final productDetailResponse = await _inAppPurchase.queryProductDetails(_kProductIds);
    if (!mounted) return;

    setState(() {
      _isAvailable = isAvailable;
      _products = productDetailResponse.productDetails;
      _loading = false;
    });
  }

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _showMessage('Compra pendiente...');
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.error) {
        _showMessage(
          purchaseDetails.error?.message ?? 'La compra falló.',
          isError: true,
        );
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        final verified = await _verifyPurchaseOnBackend(purchaseDetails);
        if (verified && purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  String _purchaseKey(PurchaseDetails purchase) {
    final token = purchase.verificationData.serverVerificationData;
    return '${purchase.productID}:$token';
  }

  Future<bool> _verifyPurchaseOnBackend(PurchaseDetails purchase) async {
    final key = _purchaseKey(purchase);
    if (_processedPurchaseKeys.contains(key)) {
      return true;
    }

    final purchaseToken = purchase.verificationData.serverVerificationData;
    if (purchaseToken.isEmpty) {
      _showMessage('Token de compra inválido.', isError: true);
      return false;
    }

    setState(() => _verifying = true);
    _showMessage('Pago recibido. Validando en el servidor...');

    try {
      final endsAt = await SubscriptionService.verifyPurchase(
        productId: purchase.productID,
        purchaseToken: purchaseToken,
        sessionToken: widget.sessionToken,
      );

      _processedPurchaseKeys.add(key);

      if (mounted) {
        setState(() {
          _verifying = false;
          _subscriptionStatus = SubscriptionStatus(
            hasActiveSubscription: true,
            globalFreeTrialActive: _subscriptionStatus?.globalFreeTrialActive ?? false,
            canAccessService: true,
            endsAt: endsAt,
          );
        });
      }

      _showMessage('Suscripción activada correctamente.');
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _verifying = false);
      _showMessage(e.message, isError: true);
      return false;
    } catch (_) {
      if (mounted) setState(() => _verifying = false);
      _showMessage('No se pudo validar la compra.', isError: true);
      return false;
    }
  }

  Future<void> _buyProduct(ProductDetails product) async {
    if (_verifying) return;

    final purchaseParam = PurchaseParam(productDetails: product);
    await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _simulateDevPurchase(String productId) async {
    if (_verifying) return;
    if (!kDebugMode) {
      _showMessage('Las compras simuladas solo están disponibles en modo debug.', isError: true);
      return;
    }

    setState(() => _verifying = true);
    _showMessage('Simulando compra de $productId...');

    try {
      final token = 'dev_${productId}_${DateTime.now().millisecondsSinceEpoch}';
      final endsAt = await SubscriptionService.verifyPurchase(
        productId: productId,
        purchaseToken: token,
        sessionToken: widget.sessionToken,
      );

      if (!mounted) return;
      setState(() {
        _verifying = false;
        _subscriptionStatus = SubscriptionStatus(
          hasActiveSubscription: true,
          globalFreeTrialActive: _subscriptionStatus?.globalFreeTrialActive ?? false,
          canAccessService: true,
          endsAt: endsAt,
        );
      });
      _showMessage('Compra simulada activada.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _verifying = false);
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (mounted) setState(() => _verifying = false);
      _showMessage('No se pudo simular la compra.', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : AppTheme.primary,
      ),
    );
  }

  Widget _buildStatusBanner() {
    final status = _subscriptionStatus;
    if (status == null) return const SizedBox.shrink();

    final endsAt = status.endsAt;
    String message;
    Color color;

    if (status.globalFreeTrialActive && !status.hasActiveSubscription) {
      message = 'Prueba gratuita global activa';
      color = Colors.greenAccent.shade400;
    } else if (status.hasActiveSubscription && endsAt != null) {
      message = 'Activo hasta ${endsAt.toLocal()}';
      color = Colors.greenAccent.shade400;
    } else {
      message = 'Sin suscripción activa';
      color = Colors.orangeAccent;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildProductCard(ProductDetails product) {
    return Card(
      color: AppTheme.surface,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        title: Text(
          product.title,
          style: const TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          product.description,
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _verifying ? null : () => _buyProduct(product),
          child: Text(product.price, style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildMockCard(String title, String price, String productId) {
    return Card(
      color: AppTheme.surface,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        title: Text(title, style: const TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold)),
        subtitle: const Text('Solo debug — requiere ALLOW_UNVERIFIED_PURCHASES=true', style: TextStyle(color: AppTheme.textMuted)),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _verifying ? null : () => _simulateDevPurchase(productId),
          child: Text(price, style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Suscripciones', style: GoogleFonts.outfit(color: AppTheme.textLight)),
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textLight),
      ),
      backgroundColor: AppTheme.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatusBanner(),
                    Text('Planes disponibles', style: GoogleFonts.outfit(fontSize: 24, color: AppTheme.textLight)),
                    const SizedBox(height: 20),
                    if (!_isAvailable)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Google Play Billing no está disponible en este dispositivo.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ..._products.map(_buildProductCard),
                    if (_products.isEmpty && kDebugMode) ...[
                      const Text('Modo debug sin Play Store', style: TextStyle(color: Colors.orange)),
                      const SizedBox(height: 10),
                      _buildMockCard('Micro - 24 horas', '\$0.49', 'sub_micro_24h'),
                      _buildMockCard('Medium - 30 días', '\$9.99', 'sub_medium_30d'),
                      _buildMockCard('Max - 180 días', '\$49.99', 'sub_max_180d'),
                    ],
                  ],
                ),
                if (_verifying)
                  Container(
                    color: Colors.black54,
                    child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                  ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
