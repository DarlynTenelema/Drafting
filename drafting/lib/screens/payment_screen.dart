import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/services/api_client.dart';
import '../core/services/subscription_service.dart';
import '../theme/app_theme.dart';

class _PlanFeature {
  final String text;
  final Widget Function(Color color)? iconBuilder;
  final IconData? iconData;

  _PlanFeature(this.text, {this.iconBuilder, this.iconData});
}

class PaymentScreen extends StatefulWidget {
  final String sessionToken;
  final String? creatorId;
  final bool isGroup;
  const PaymentScreen({super.key, required this.sessionToken, this.creatorId, this.isGroup = false});

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
    'plus_1d', 'plus_1w', 'plus_1m', 'plus_1y',
    'pro_1d', 'pro_1w', 'pro_1m', 'pro_1y',
    'ultra_1d', 'ultra_1w', 'ultra_1m', 'ultra_1y',
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
    List<ProductDetails> products = [];

    if (isAvailable) {
      final productDetailResponse = await _inAppPurchase.queryProductDetails(_kProductIds);
      products = productDetailResponse.productDetails;
    }

    
    // --- INICIO MOCK DATA ---
    if (products.isEmpty) {
      products = _kProductIds.map((id) {
        String title = 'Plan';
        String price = '\$0.99';

        if (id.startsWith('plus')) {
          title = 'Plus';
          if (id.contains('1d')) price = '\$0.24';
          else if (id.contains('1w')) price = '\$1.58';
          else if (id.contains('1m')) price = '\$5.99';
          else if (id.contains('1y')) price = '\$59.99';
        } else if (id.startsWith('pro')) {
          title = 'Pro';
          if (id.contains('1d')) price = '\$0.49';
          else if (id.contains('1w')) price = '\$2.99';
          else if (id.contains('1m')) price = '\$9.99';
          else if (id.contains('1y')) price = '\$99.99';
        } else if (id.startsWith('ultra')) {
          title = 'Ultra';
          if (id.contains('1d')) price = '\$0.99';
          else if (id.contains('1w')) price = '\$5.99';
          else if (id.contains('1m')) price = '\$19.99';
          else if (id.contains('1y')) price = '\$199.99';
        }
        
        return ProductDetails(
          id: id,
          title: title,
          description: 'Suscripción de prueba (Prepago)',
          price: price,
          rawPrice: 1.0,
          currencyCode: 'USD',
        );
      }).toList();
    }
    // --- FIN MOCK DATA ---

    if (!mounted) return;

    setState(() {
      _isAvailable = isAvailable || products.isNotEmpty;
      _products = products;
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
      if (widget.creatorId != null) {
        if (widget.isGroup) {
          await SubscriptionService.subscribeGroup(
            subscriptionId: purchase.productID,
            purchaseToken: purchaseToken,
            sessionToken: widget.sessionToken,
            groupId: widget.creatorId!,
          );
        } else {
          await SubscriptionService.subscribeCreator(
            subscriptionId: purchase.productID,
            purchaseToken: purchaseToken,
            sessionToken: widget.sessionToken,
            creatorId: widget.creatorId!,
          );
        }
        _processedPurchaseKeys.add(key);

        if (mounted) {
          setState(() {
            _verifying = false;
          });
          _showMessage('¡Sistema de IA activado correctamente!');
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.pop(context, true);
          });
        }
        return true;
      } else {
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
      }
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
    // Como son planes prepago (renovables manualmente) y en Google Play 
    // están como Productos Únicos, deben tratarse como consumibles 
    // para que Google Play permita volver a comprarlos una vez expiren.
    await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam, autoConsume: true);
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
    required List<_PlanFeature> features,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 15,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(Icons.stars, color: color, size: 28),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price,
                style: GoogleFonts.outfit(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 24),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildFeatureRow(f, color),
          )),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(_PlanFeature feature, Color iconColor) {
    Widget iconWidget;
    if (feature.iconBuilder != null) {
      iconWidget = feature.iconBuilder!(iconColor);
    } else if (feature.iconData != null) {
      iconWidget = Icon(feature.iconData, color: iconColor, size: 20);
    } else {
      iconWidget = Icon(Icons.check_circle, color: iconColor, size: 20);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        iconWidget,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            feature.text,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdsBlockIcon(Color color) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'ADS',
            style: GoogleFonts.outfit(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: color.withValues(alpha: 0.7),
            ),
          ),
          Icon(Icons.block, color: color, size: 20),
        ],
      ),
    );
  }



  String _cleanTitle(String rawTitle) {
    // Google Play siempre añade " (NombreApp)" al final del título.
    final index = rawTitle.indexOf(' (');
    if (index != -1) {
      return rawTitle.substring(0, index);
    }
    return rawTitle;
  }


  Widget _buildDurationTab(List<ProductDetails> tabProducts) {
    if (!_isAvailable) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Google Play Billing no está disponible.', style: TextStyle(color: Colors.orange)),
      );
    }
    
    // Sort products: plus -> pro -> ultra
    tabProducts.sort((a, b) {
      final order = {'plus': 0, 'pro': 1, 'ultra': 2};
      int wA = order[a.id.split('_').first] ?? 0;
      int wB = order[b.id.split('_').first] ?? 0;
      return wA.compareTo(wB);
    });

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildStatusBanner(),
        
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.greenAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Todos nuestros planes son In-App Purchases de pago único. Tú decides cuándo renovar.',
                  style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        ...tabProducts.map((p) {
          final isPlus = p.id.startsWith('plus');
          final isPro = p.id.startsWith('pro');
          final isUltra = p.id.startsWith('ultra');
          
          Color tierColor = Colors.blueAccent;
          List<_PlanFeature> features = [];
          
          if (isPlus) {
            tierColor = Colors.blue.shade900;
            features = [
              _PlanFeature('Consulta el mejor pick para tu partida', iconBuilder: (c) => Image.asset('assets/images/rift_outline.png', color: c, width: 20, height: 20)),
              _PlanFeature('10 consultas por hora', iconData: Icons.hourglass_empty),
              _PlanFeature('Sin anuncios', iconBuilder: (c) => _buildAdsBlockIcon(c)),
            ];
          } else if (isPro) {
            tierColor = Colors.blue;
            features = [
              _PlanFeature('Consulta el mejor pick para tu partida', iconBuilder: (c) => Image.asset('assets/images/rift_outline.png', color: c, width: 20, height: 20)),
              _PlanFeature('Consulta las mejores runas para tu OTP', iconBuilder: (c) => Image.asset('assets/images/mastery_outline.png', color: c, width: 20, height: 20)),
              _PlanFeature('Consulta los objetos adecuados en partida', iconData: Icons.shopping_bag_outlined),
              _PlanFeature('30 consultas por hora', iconData: Icons.hourglass_empty),
              _PlanFeature('Sin anuncios', iconBuilder: (c) => _buildAdsBlockIcon(c)),
              _PlanFeature('1000 esencias azules', iconBuilder: (c) => Image.asset('assets/images/crystal_coin_outline.png', color: c, width: 20, height: 20)),
            ];
          } else if (isUltra) {
            tierColor = Colors.lightBlueAccent;
            features = [
              _PlanFeature('Consulta el mejor pick para tu partida', iconBuilder: (c) => Image.asset('assets/images/rift_outline.png', color: c, width: 20, height: 20)),
              _PlanFeature('Consulta las mejores runas para tu OTP', iconBuilder: (c) => Image.asset('assets/images/mastery_outline.png', color: c, width: 20, height: 20)),
              _PlanFeature('Consulta los objetos adecuados en partida', iconData: Icons.shopping_bag_outlined),
              _PlanFeature('30 consultas por hora', iconData: Icons.hourglass_empty),
              _PlanFeature('Acceso al Chat Coach (CC)', iconData: Icons.headset_mic),
              _PlanFeature('5 Millones de tokens a la semana', iconData: Icons.memory),
              if (p.id.endsWith('_1m') || p.id.endsWith('_1y'))
                _PlanFeature('3 GB de almacenamiento en la nube (Permanente)', iconData: Icons.cloud_done_outlined),
              _PlanFeature('Sin anuncios', iconBuilder: (c) => _buildAdsBlockIcon(c)),
              _PlanFeature('1000 esencias azules', iconBuilder: (c) => Image.asset('assets/images/crystal_coin_outline.png', color: c, width: 20, height: 20)),
              _PlanFeature('Más campos de texto para ajustar tu IA', iconData: Icons.build),
            ];
          }

          return _buildSubscriptionCard(
            title: _cleanTitle(p.title),
            description: p.description,
            price: p.price,
            features: features,
            color: tierColor,
            onPressed: () => _buyProduct(p),
          );
        }).toList(),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final dailyProducts = _products.where((p) => p.id.endsWith('_1d')).toList();
    final weeklyProducts = _products.where((p) => p.id.endsWith('_1w')).toList();
    final monthlyProducts = _products.where((p) => p.id.endsWith('_1m')).toList();
    final yearlyProducts = _products.where((p) => p.id.endsWith('_1y')).toList();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Planes y Accesos', style: GoogleFonts.outfit(color: AppTheme.textLight)),
          backgroundColor: AppTheme.background,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppTheme.textLight),
          bottom: TabBar(
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textMuted,
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            isScrollable: true,
            tabs: const [
              Tab(text: 'Diario'),
              Tab(text: 'Semanal'),
              Tab(text: 'Mensual'),
              Tab(text: 'Anual'),
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
                      _buildDurationTab(dailyProducts),
                      _buildDurationTab(weeklyProducts),
                      _buildDurationTab(monthlyProducts),
                      _buildDurationTab(yearlyProducts),
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
