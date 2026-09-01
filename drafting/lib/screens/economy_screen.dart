import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/services/finance_service.dart';

import '../theme/app_theme.dart';

class EconomyScreen extends StatefulWidget {
  const EconomyScreen({super.key});

  @override
  State<EconomyScreen> createState() => _EconomyScreenState();
}

class _EconomyScreenState extends State<EconomyScreen> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  List<ProductDetails> _products = [];
  bool _isCoinPressed = false;
  bool _isAvailable = false;
  bool _loading = true;
  bool _purchasing = false;

  final FinanceService _financeService = FinanceService();
  double _currentBalance = 0;

  static const Set<String> _kProductIds = {
    'essence_pack_250',
    'essence_pack_500',
    'essence_pack_1000',
    'essence_pack_3000',
    'essence_pack_5000',
  };

  @override
  void initState() {
    super.initState();
    _subscription = _inAppPurchase.purchaseStream.listen(
      _listenToPurchaseUpdated,
      onDone: () => _subscription.cancel(),
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error')));
        }
      },
    );
    _initStoreAndBalance();
  }

  Future<void> _initStoreAndBalance() async {
    await _financeService.fetchDashboardStats();
    if (mounted) {
      setState(() {
        _currentBalance = _financeService.totalCoins;
      });
    }

    final isAvailable = await _inAppPurchase.isAvailable();
    if (!isAvailable) {
      if (mounted) {
        setState(() {
          _isAvailable = false;
          _loading = false;
        });
      }
      return;
    }

    final productDetailResponse = await _inAppPurchase.queryProductDetails(_kProductIds);
    if (mounted) {
      setState(() {
        _isAvailable = true;
        _products = productDetailResponse.productDetails;
        // Sort products by price
        _products.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
        _loading = false;
      });
    }
  }

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _purchasing = true);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(purchaseDetails.error?.message ?? 'Error en la compra'), backgroundColor: Colors.red),
            );
          }
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          
          final token = purchaseDetails.verificationData.serverVerificationData;
          final success = await _financeService.rechargeCoins(purchaseDetails.productID, token);
          
          if (success) {
            if (mounted) {
              setState(() {
                _currentBalance = _financeService.totalCoins;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Esencias acreditadas exitosamente'), backgroundColor: Colors.green),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('El pago se realizó pero falló la verificación en el servidor.'), backgroundColor: Colors.orange),
              );
            }
          }
        }
        
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
        if (mounted) setState(() => _purchasing = false);
      }
    }
  }

  void _purchasePackage(ProductDetails product) {
    if (_purchasing) return;
    final purchaseParam = PurchaseParam(productDetails: product);
    _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
  }



  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Tienda',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Ambient Glow Background
          Positioned(
            top: -100,
            left: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00BFFF).withValues(alpha: 0.15), // Blue glow
                ),
              ),
            ),
          ),
          
          Column(
            children: [
              // 3D Viewer Area
              const SizedBox(height: 80),
              Expanded(
                flex: 4,
                child: SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => _isCoinPressed = true),
                  onTapUp: (_) => setState(() => _isCoinPressed = false),
                  onTapCancel: () => setState(() => _isCoinPressed = false),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _isCoinPressed ? 220 : 200,
                      height: _isCoinPressed ? 220 : 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: _isCoinPressed ? 0.6 : 0.1),
                            blurRadius: _isCoinPressed ? 60 : 30,
                            spreadRadius: _isCoinPressed ? 10 : 0,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/crystal_coin.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Current Balance HUD
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF00BFFF).withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00BFFF).withValues(alpha: 0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/crystal_coin.png', width: 32, height: 32),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tu Saldo Actual',
                          style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                        ),
                        Text(
                          '${_currentBalance.toInt()}',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              
              // Packages List
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                  child: RefreshIndicator(
                    color: AppTheme.primary,
                    backgroundColor: AppTheme.surface,
                    onRefresh: _initStoreAndBalance,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.only(top: 24, bottom: 40),
                    children: [
                      Text(
                        'Paquetes de Esencias Azules',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_loading) 
                        const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppTheme.primary)))
                      else if (!_isAvailable)
                        const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text('La tienda no está disponible en este dispositivo.', style: TextStyle(color: Colors.orange)),
                        )
                      else if (_products.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text('No hay paquetes disponibles en este momento.', style: TextStyle(color: Colors.orange)),
                        )
                      else
                        ..._products.map((p) {
                          // Extract amount of coins from title or id if possible, just passing title for now.
                          int coins = 0;
                          if (p.id == 'essence_pack_250') coins = 250;
                          if (p.id == 'essence_pack_500') coins = 500;
                          if (p.id == 'essence_pack_1000') coins = 1000;
                          if (p.id == 'essence_pack_3000') coins = 3000;
                          if (p.id == 'essence_pack_5000') coins = 5000;
                          
                          return _buildRealPackageCard(p, coins, isPopular: p.id == 'essence_pack_1000');
                        }),
                    ],
                  ),
                  ),
                ),
              ),
            ],
          ),
          
          if (_purchasing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            ),
        ],
      ),
    );
  }

  Widget _buildRealPackageCard(ProductDetails product, int coins, {bool isPopular = false}) {
    return GestureDetector(
      onTap: () => _purchasePackage(product),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPopular ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPopular ? AppTheme.primary : Colors.white.withValues(alpha: 0.1),
            width: isPopular ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Image.asset('assets/images/crystal_coin.png', width: 40, height: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _cleanTitle(product.title),
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isPopular)
                          Text(
                            '¡Más Popular!',
                            style: GoogleFonts.inter(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold),
                          )
                        else
                          Text(
                            '$coins Esencias',
                            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isPopular ? AppTheme.primary : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                product.price,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }



  String _cleanTitle(String rawTitle) {
    final index = rawTitle.indexOf(' (');
    if (index != -1) {
      return rawTitle.substring(0, index);
    }
    return rawTitle;
  }
}
