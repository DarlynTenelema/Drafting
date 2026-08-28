import '../core/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:convert';
import '../theme/app_theme.dart';
import '../core/state/active_product_state.dart';
import '../core/services/subscription_service.dart';
import 'payment_screen.dart';

class ConsumerStoreScreen extends StatefulWidget {
  final String sessionToken;
  const ConsumerStoreScreen({super.key, required this.sessionToken});

  @override
  State<ConsumerStoreScreen> createState() => _ConsumerStoreScreenState();
}

class ProductItem {
  final String id;
  final String title;
  final String subtitle;
  final String champion;
  final bool isGroup;
  final String author;
  final double price;
  final Color primaryColor;
  final String imageUrl;

  ProductItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.champion,
    required this.isGroup,
    required this.author,
    required this.price,
    required this.primaryColor,
    required this.imageUrl,
  });

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    Color parsedColor = AppTheme.primary;
    if (json['primary_color'] != null) {
      String hexColor = json['primary_color'];
      if (hexColor.startsWith('0x')) {
        parsedColor = Color(int.parse(hexColor));
      }
    }
    return ProductItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      champion: json['champion'] ?? '',
      isGroup: json['is_group'] ?? false,
      author: json['author'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      primaryColor: parsedColor,
      imageUrl: json['image_url'] ?? '',
    );
  }
}

class _ConsumerStoreScreenState extends State<ConsumerStoreScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<ProductItem> _products = [];
  List<ProductItem> _myPackages = [];
  
  bool _isLoading = true;
  bool _isLoadingMyPackages = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchProducts();
    _fetchMyPackages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    try {
      final response = await ApiClient.get('/store/products');
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _products = data.map((item) => ProductItem.fromJson(item)).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Error al cargar la tienda.";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error de conexión: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchMyPackages() async {
    setState(() => _isLoadingMyPackages = true);
    try {
      final data = await SubscriptionService.getMyPackages(sessionToken: widget.sessionToken);
      if (mounted) {
        setState(() {
          _myPackages = data.map((item) => ProductItem.fromJson(item as Map<String, dynamic>)).toList();
          _isLoadingMyPackages = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMyPackages = false;
        });
      }
    }
  }

  void _purchaseProduct(ProductItem product) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentScreen(
          sessionToken: widget.sessionToken,
          creatorId: product.id,
          isGroup: product.isGroup,
        ),
      ),
    );

    if (result == true) {
      // Purchase was successful
      await _fetchMyPackages();
      _tabController.animateTo(1); // Switch to "Mis Sistemas IA" tab
    }
  }

  void _activateProduct(ProductItem product) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 24),
              Text(
                'Activando sistema IA...',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Simulando pago y configuración de ${product.title}',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );

    // Simulate network delay
    Future.delayed(const Duration(seconds: 2), () async {
      await ActiveProductState().setActiveProduct(product.title, product.id);
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _showSuccess(product);
      }
    });
  }

  void _showSuccess(ProductItem product) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(32),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 64),
              ),
              const SizedBox(height: 24),
              Text(
                '¡Sistema Activado!',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Has activado exitosamente "${product.title}". La Inteligencia Artificial ahora utilizará este conocimiento en tus partidas.',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 15, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close success modal
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    'Entendido',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Tienda de Creadores',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Explorar'),
            Tab(text: 'Mis Sistemas IA'),
          ],
        ),
      ),
      body: ValueListenableBuilder<String?>(
        valueListenable: ActiveProductState().activeProductNotifier,
        builder: (context, activeProduct, child) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildExploreTab(activeProduct),
              _buildMyPackagesTab(activeProduct),
            ],
          );
        }
      ),
    );
  }

  Widget _buildExploreTab(String? activeProduct) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)));
    }
    if (_products.isEmpty) {
      return const Center(child: Text('No hay productos disponibles por ahora.', style: TextStyle(color: Colors.white)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24.0),
      itemCount: _products.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mejora tu Inteligencia Artificial',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Activa paquetes de conocimiento creados por los mejores jugadores del mundo.',
                  style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 15),
                ),
              ],
            ),
          );
        }
        final product = _products[index - 1];
        return _buildProductCard(product, activeProduct == product.title, false);
      },
    );
  }

  Widget _buildMyPackagesTab(String? activeProduct) {
    if (_isLoadingMyPackages) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_myPackages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: AppTheme.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                'Aún no tienes sistemas IA',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Los paquetes que adquieras en Explorar aparecerán aquí listos para ser activados.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24.0),
      itemCount: _myPackages.length,
      itemBuilder: (context, index) {
        final product = _myPackages[index];
        return _buildProductCard(product, activeProduct == product.title, true);
      },
    );
  }

  Widget _buildProductCard(ProductItem product, bool isActive, bool isOwned) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            product.primaryColor.withValues(alpha: 0.15),
            AppTheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: product.primaryColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: product.primaryColor.withValues(alpha: 0.05),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.imageUrl.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    image: DecorationImage(
                      image: NetworkImage(product.imageUrl),
                      fit: BoxFit.cover,
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Creado por @${product.author}',
                      style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: product.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: product.primaryColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(product.isGroup ? Icons.group : Icons.person, color: product.primaryColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      product.isGroup ? 'Grupo' : 'OTP',
                      style: GoogleFonts.inter(color: product.primaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            product.subtitle,
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isOwned) ...[
                Text(
                  '\$${product.price}',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
                  child: Text('/ mes', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14)),
                ),
              ],
              const Spacer(),
              if (isActive && isOwned)
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: Text('En Uso', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                )
              else if (isOwned)
                ElevatedButton.icon(
                  onPressed: () => _activateProduct(product),
                  icon: const Icon(Icons.power_settings_new, color: Colors.white),
                  label: Text('Activar', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: product.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                    shadowColor: product.primaryColor.withValues(alpha: 0.5),
                  ),
                )
              else 
                ElevatedButton.icon(
                  onPressed: () => _purchaseProduct(product),
                  icon: const Icon(Icons.shopping_cart, color: Colors.white),
                  label: Text('Adquirir', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: product.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                    shadowColor: product.primaryColor.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
