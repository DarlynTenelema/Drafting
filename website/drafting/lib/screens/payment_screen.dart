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

  Widget _buildSubscriptionCard({
    required String title,
    required String description,
    required String price,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textLight,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            price,
            style: GoogleFonts.outfit(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _verifying ? null : onPressed,
              child: Text(
                'Obtener Plan',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: AppTheme.textMuted, height: 1),
          const SizedBox(height: 24),
          _buildFeatureRow('Límites de uso ilimitados por la duración.'),
          const SizedBox(height: 12),
          _buildFeatureRow('Acceso al modelo de IA avanzado para Draft.'),
          const SizedBox(height: 12),
          _buildFeatureRow('Recomendaciones instantáneas de campeones.'),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check, color: AppTheme.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textLight,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _getMockCardsForPrefix(String prefix) {
    if (prefix == 'micro') {
      return [
        _buildSubscriptionCard(title: 'Micro - 24 horas', description: 'Solo debug', price: '\$0.49', onPressed: () => _simulateDevPurchase('sub_micro_24h')),
        _buildSubscriptionCard(title: 'Micro - 72 horas', description: 'Solo debug', price: '\$1.47', onPressed: () => _simulateDevPurchase('sub_micro_72h')),
        _buildSubscriptionCard(title: 'Micro - 120 horas', description: 'Solo debug', price: '\$2.45', onPressed: () => _simulateDevPurchase('sub_micro_120h')),
      ];
    } else if (prefix == 'medium') {
      return [
        _buildSubscriptionCard(title: 'Medium - 30 días', description: 'Solo debug', price: '\$9.99', onPressed: () => _simulateDevPurchase('sub_medium_30d')),
        _buildSubscriptionCard(title: 'Medium - 90 días', description: 'Solo debug', price: '\$29.97', onPressed: () => _simulateDevPurchase('sub_medium_90d')),
        _buildSubscriptionCard(title: 'Medium - 150 días', description: 'Solo debug', price: '\$49.95', onPressed: () => _simulateDevPurchase('sub_medium_150d')),
      ];
    } else {
      return [
        _buildSubscriptionCard(title: 'Max - 180 días', description: 'Solo debug', price: '\$49.99', onPressed: () => _simulateDevPurchase('sub_max_180d')),
        _buildSubscriptionCard(title: 'Max - 240 días', description: 'Solo debug', price: '\$79.99', onPressed: () => _simulateDevPurchase('sub_max_240d')),
        _buildSubscriptionCard(title: 'Max - 365 días', description: 'Solo debug', price: '\$99.99', onPressed: () => _simulateDevPurchase('sub_max_365d')),
      ];
    }
  }

  String _cleanTitle(String rawTitle) {
    // Google Play siempre añade " (NombreApp)" al final del título.
    final index = rawTitle.indexOf(' (');
    if (index != -1) {
      return rawTitle.substring(0, index);
    }
    return rawTitle;
  }

  Widget _buildTabContent(List<ProductDetails> tabProducts, String prefix) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildStatusBanner(),
        if (!_isAvailable)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Google Play Billing no está disponible en este dispositivo.',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ...tabProducts.map((p) => _buildSubscriptionCard(
              title: _cleanTitle(p.title),
              description: p.description,
              price: p.price,
              onPressed: () => _buyProduct(p),
            )),
        if (_products.isEmpty && kDebugMode) ..._getMockCardsForPrefix(prefix),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final microProducts = _products.where((p) => p.id.startsWith('sub_micro')).toList();
    final mediumProducts = _products.where((p) => p.id.startsWith('sub_medium')).toList();
    final maxProducts = _products.where((p) => p.id.startsWith('sub_max')).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Suscripciones', style: GoogleFonts.outfit(color: AppTheme.textLight)),
          backgroundColor: AppTheme.background,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppTheme.textLight),
          bottom: TabBar(
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textMuted,
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'Micro'),
              Tab(text: 'Medium'),
              Tab(text: 'Max'),
            ],
          ),
        ),
        backgroundColor: AppTheme.background,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  TabBarView(
                    children: [
                      _buildTabContent(microProducts, 'micro'),
                      _buildTabContent(mediumProducts, 'medium'),
                      _buildTabContent(maxProducts, 'max'),
                    ],
                  ),
                  if (_verifying)
                    Container(
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                    ),
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
