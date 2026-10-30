import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/services/api_client.dart';
import '../core/services/iap_service.dart';

class StoreScreen extends StatefulWidget {
  final VoidCallback onDataChanged;
  final bool isTab;

  const StoreScreen({
    super.key,
    required this.onDataChanged,
    this.isTab = false,
  });

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  // Datos del catálogo y usuario
  bool _hasPurchasedStarter = false;
  bool _isSubscribed = false;
  String _subscriptionPlan = 'none';
  int _availableQueries = 0;
  int _subscriptionQueries = 0;
  int _purchasedQueries = 0;
  int _dailyTransferredToday = 0;
  int _remainingTransferQuota = 10;
  bool _canTransfer = false;

  List<dynamic> _packs = [];
  List<dynamic> _subscriptions = [];

  // Controladores para compartir consultas
  final TextEditingController _friendIdController = TextEditingController();
  int _selectedTransferAmount = 5;
  bool _isTransferring = false;
  bool _isPurchasing = false;

  StreamSubscription<IapPurchaseResult>? _iapSubscription;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
    _initIap();
  }

  void _initIap() {
    InAppPurchaseService.instance.initialize();
    _iapSubscription = InAppPurchaseService.instance.onPurchaseResult.listen((result) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);

      if (result.success) {
        HapticFeedback.heavyImpact();
        widget.onDataChanged();
        _fetchCatalog();

        _showCelebrationDialog(
          title: result.isSubscription ? '¡Suscripción Activada!' : '¡Paquete Adquirido!',
          message: result.message ?? 'Se han acreditado las consultas con éxito.',
          queries: result.queriesAdded,
        );
      } else {
        if (result.message != null &&
            result.message!.isNotEmpty &&
            !result.message!.toLowerCase().contains('cancelada') &&
            !result.message!.toLowerCase().contains('canceled')) {
          _showErrorSnackBar(result.message!);
        }
      }
    });
  }

  @override
  void dispose() {
    _iapSubscription?.cancel();
    _friendIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchCatalog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiClient.get('/api/v1/store/catalog', authenticated: true);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _hasPurchasedStarter = data['has_purchased_starter'] ?? false;
            _isSubscribed = data['is_subscribed'] ?? false;
            _subscriptionPlan = data['subscription_plan'] ?? 'none';
            _availableQueries = data['available_queries'] ?? 0;
            _subscriptionQueries = data['subscription_queries'] ?? 0;
            _purchasedQueries = data['purchased_queries'] ?? 0;
            _dailyTransferredToday = data['daily_transferred_today'] ?? 0;
            _remainingTransferQuota = data['remaining_transfer_quota'] ?? 10;
            _canTransfer = data['can_transfer'] ?? false;
            _packs = data['packs'] ?? [];
            _subscriptions = data['subscriptions'] ?? [];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Error al cargar la tienda. Código: ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No se pudo conectar con el servidor: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _buyPack(Map<String, dynamic> pack) async {
    if (_isPurchasing) return;

    setState(() => _isPurchasing = true);
    HapticFeedback.mediumImpact();

    final packId = pack['id'] ?? '';
    final launched = await InAppPurchaseService.instance.buyPack(packId);
    if (!launched && mounted) {
      setState(() => _isPurchasing = false);
    }
  }

  Future<void> _subscribe(Map<String, dynamic> sub) async {
    if (_isPurchasing) return;

    setState(() => _isPurchasing = true);
    HapticFeedback.mediumImpact();

    final planId = sub['id'] ?? '';
    final launched = await InAppPurchaseService.instance.buySubscription(planId);
    if (!launched && mounted) {
      setState(() => _isPurchasing = false);
    }
  }

  Future<void> _transferQueries() async {
    final rawTarget = _friendIdController.text.trim();
    if (rawTarget.isEmpty) {
      _showErrorSnackBar('Ingresa el ID o código de tu amigo (ej. EW3J43).');
      return;
    }

    if (!_isSubscribed) {
      _showSubscriptionRequiredDialog();
      return;
    }

    if (_remainingTransferQuota <= 0) {
      _showErrorSnackBar('Ya alcanzaste el límite diario de 10 consultas transferidas hoy.');
      return;
    }

    if (_selectedTransferAmount > _remainingTransferQuota) {
      _showErrorSnackBar('Solo puedes transferir hasta $_remainingTransferQuota consultas más hoy.');
      return;
    }

    setState(() => _isTransferring = true);
    HapticFeedback.mediumImpact();

    try {
      final response = await ApiClient.post(
        '/api/v1/store/transfer-queries',
        authenticated: true,
        body: {
          'target_player_id': rawTarget,
          'amount': _selectedTransferAmount,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        HapticFeedback.heavyImpact();
        _friendIdController.clear();
        widget.onDataChanged();
        await _fetchCatalog();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      data['message'] ?? '¡Consultas transferidas con éxito!',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        final errorMsg = response.body.isNotEmpty ? response.body : 'Error al transferir consultas';
        _showErrorSnackBar(errorMsg);
      }
    } catch (e) {
      _showErrorSnackBar('Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: GoogleFonts.outfit(color: Colors.white),
        ),
      ),
    );
  }

  void _showCelebrationDialog({
    required String title,
    required String message,
    required int queries,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFC89B3C), width: 1.5),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC89B3C).withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.bolt_rounded, size: 48, color: Color(0xFF00E5FF)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '+$queries Consultas Listas',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF10B981),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC89B3C),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  '¡A la Ranked!',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubscriptionRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_person_rounded, size: 44, color: Color(0xFF00E5FF)),
            const SizedBox(height: 14),
            Text(
              'Comparte con tu Dúo',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'La función de compartir hasta 10 consultas por día con tus amigos está disponible para suscriptores y usuarios con Pack Starter.\n\n¡Apoya a tu compañero desde solo \$0.19!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Ver Planes de Suscripción'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        automaticallyImplyLeading: !widget.isTab,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_rounded, color: Color(0xFFC89B3C), size: 22),
            const SizedBox(width: 8),
            Text(
              'Tienda & Pases',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_rounded, color: Colors.white70),
            tooltip: 'Restaurar Compras',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1E293B),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  content: Text(
                    'Verificando compras activas en Google Play...',
                    style: GoogleFonts.outfit(color: Colors.white),
                  ),
                ),
              );
              await InAppPurchaseService.instance.restorePurchases();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _fetchCatalog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 48),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchCatalog,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
                          child: const Text('Reintentar', style: TextStyle(color: Colors.black)),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchCatalog,
                  color: const Color(0xFF00E5FF),
                  backgroundColor: const Color(0xFF0F172A),
                  child: ListView(
                    padding: const EdgeInsets.only(left: 18, right: 18, top: 16, bottom: 100),
                    children: [
                      // --- TARJETA DE SALDO Y ESTADO ACTUAL ---
                      _buildUserStatusCard(),

                      const SizedBox(height: 24),

                      // --- 1. PAQUETES DE CONSULTAS (COMPRAS ÚNICAS) ---
                      _buildSectionHeader(
                        title: 'Paquetes de Consultas',
                        subtitle: 'Consultas permanentes que nunca caducan',
                        icon: Icons.all_inclusive_rounded,
                        color: const Color(0xFF00E5FF),
                      ),
                      const SizedBox(height: 14),

                      // Tarjetas de Paquetes
                      ..._packs.map((pack) => _buildPackCard(pack)),

                      const SizedBox(height: 28),

                      // --- 2. SUSCRIPCIONES MENSUALES ---
                      _buildSectionHeader(
                        title: 'Pases Mensuales (Mayor Ahorro)',
                        subtitle: 'Recarga masiva cada mes + Enviar consultas a amigos',
                        icon: Icons.workspace_premium_rounded,
                        color: const Color(0xFFC89B3C),
                      ),
                      const SizedBox(height: 14),

                      // Tarjetas de Suscripciones
                      ..._subscriptions.map((sub) => _buildSubscriptionCard(sub)),

                      const SizedBox(height: 28),

                      // --- 3. SISTEMA VIRAL: COMPARTIR CON TU DÚO ---
                      _buildShareQueriesCard(),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildUserStatusCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: _isSubscribed ? const Color(0xFFC89B3C).withValues(alpha: 0.4) : const Color(0xFF00E5FF).withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_isSubscribed ? const Color(0xFFC89B3C) : const Color(0xFF00E5FF)).withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      _isSubscribed ? Icons.military_tech_rounded : Icons.bolt_rounded,
                      color: _isSubscribed ? const Color(0xFFC89B3C) : const Color(0xFF00E5FF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Tu Saldo Disponible',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isSubscribed ? const Color(0xFFC89B3C).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isSubscribed ? const Color(0xFFC89B3C).withValues(alpha: 0.5) : Colors.white12,
                  ),
                ),
                child: Text(
                  _isSubscribed ? 'PASSE ${_subscriptionPlan.toUpperCase()}' : 'PLAN GRATIS',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _isSubscribed ? const Color(0xFFC89B3C) : Colors.white60,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$_availableQueries',
                style: GoogleFonts.outfit(
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Consultas',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: const Color(0xFF00E5FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (_isSubscribed) ...[
            const SizedBox(height: 6),
            Text(
              '$_subscriptionQueries consultas mensuales vigentes.',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
          if (_purchasedQueries > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$_purchasedQueries consultas permanentes adquiridas.',
              style: TextStyle(fontSize: 12, color: const Color(0xFF00E5FF).withValues(alpha: 0.8)),
            ),
          ],
          if (_hasPurchasedStarter) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 14),
                const SizedBox(width: 4),
                Text(
                  'Pack Starter de bienvenida canjeado',
                  style: TextStyle(fontSize: 11, color: const Color(0xFF10B981).withValues(alpha: 0.8)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPackCard(dynamic pack) {
    final bool isStarter = pack['is_starter'] ?? false;
    final String tag = pack['tag'] ?? '';
    final int queries = pack['queries'] ?? 0;
    final int bonus = pack['bonus_queries'] ?? 0;
    final double price = (pack['price_usd'] as num).toDouble();

    Color borderColor = Colors.white.withValues(alpha: 0.08);
    Color tagBgColor = const Color(0xFF00E5FF).withValues(alpha: 0.15);
    Color tagTextColor = const Color(0xFF00E5FF);

    if (isStarter) {
      borderColor = const Color(0xFF10B981).withValues(alpha: 0.4);
      tagBgColor = const Color(0xFF10B981).withValues(alpha: 0.2);
      tagTextColor = const Color(0xFF10B981);
    } else if (pack['id'] == 'pro') {
      borderColor = const Color(0xFFC89B3C).withValues(alpha: 0.5);
      tagBgColor = const Color(0xFFC89B3C).withValues(alpha: 0.2);
      tagTextColor = const Color(0xFFC89B3C);
    } else if (pack['id'] == 'ultra') {
      borderColor = const Color(0xFF8B5CF6).withValues(alpha: 0.5);
      tagBgColor = const Color(0xFF8B5CF6).withValues(alpha: 0.2);
      tagTextColor = const Color(0xFFC4B5FD);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isPurchasing ? null : () => _buyPack(pack),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Ícono distintivo del paquete
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tagTextColor.withValues(alpha: 0.15),
                    border: Border.all(color: tagTextColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    isStarter
                        ? Icons.card_giftcard_rounded
                        : (pack['id'] == 'pack_pro' || pack['id'] == 'pro')
                            ? Icons.auto_awesome_rounded
                            : (pack['id'] == 'pack_ultra' || pack['id'] == 'ultra')
                                ? Icons.diamond_rounded
                                : Icons.bolt_rounded,
                    color: tagTextColor,
                    size: 22,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              pack['name'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (tag.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: tagBgColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tag.toUpperCase(),
                                style: GoogleFonts.outfit(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: tagTextColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '$queries Consultas',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF00E5FF),
                            ),
                          ),
                          if (bonus > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(+$bonus regalo)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pack['description'] ?? '',
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _isPurchasing ? null : () => _buyPack(pack),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isStarter ? const Color(0xFF10B981) : const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    InAppPurchaseService.instance.getDisplayPrice(
                      pack['id'] ?? '',
                      '\$${price.toStringAsFixed(2)}',
                    ),
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard(dynamic sub) {
    final double price = (sub['price_usd'] as num).toDouble();
    final int queries = sub['queries_per_month'] ?? 0;
    final bool isCurrentPlan = _isSubscribed && _subscriptionPlan == sub['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentPlan ? const Color(0xFFC89B3C) : const Color(0xFFC89B3C).withValues(alpha: 0.25),
          width: isCurrentPlan ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isPurchasing ? null : () => _subscribe(sub),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Ícono distintivo de suscripción
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFC89B3C).withValues(alpha: 0.15),
                    border: Border.all(color: const Color(0xFFC89B3C).withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    (sub['id'] == 'sub_ultra' || sub['id'] == 'ultra')
                        ? Icons.workspace_premium_rounded
                        : (sub['id'] == 'sub_pro' || sub['id'] == 'pro')
                            ? Icons.military_tech_rounded
                            : Icons.shield_rounded,
                    color: const Color(0xFFC89B3C),
                    size: 22,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              sub['name'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC89B3C).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sub['tag'] ?? '',
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFC89B3C),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$queries Consultas / mes',
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFC89B3C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sub['description'] ?? '',
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _isPurchasing ? null : () => _subscribe(sub),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCurrentPlan ? const Color(0xFF10B981) : const Color(0xFFC89B3C),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isCurrentPlan
                        ? 'Activo'
                        : InAppPurchaseService.instance.getDisplayPrice(
                            sub['id'] ?? '',
                            '\$${price.toStringAsFixed(2)}/mes',
                          ),
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShareQueriesCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isSubscribed ? const Color(0xFF10B981).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.share_rounded, color: Color(0xFF10B981), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Compartir con tu Dúo / Amigos',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Regala consultas a compañeros de tu squad',
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Cuota diaria de transferencia
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cuota para enviar hoy:',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                ),
                Text(
                  '$_dailyTransferredToday enviadas | $_remainingTransferQuota restantes',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _canTransfer ? const Color(0xFF10B981) : Colors.amberAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Campo: ID del Jugador
          Text(
            'ID o Código del Jugador (ej. EW3J43):',
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _friendIdController,
            textCapitalization: TextCapitalization.characters,
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'Ingresa el ID del jugador',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF00E5FF)),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Selector de cantidad de consultas (1 a 10)
          Text(
            'Cantidad de Consultas a Enviar: $_selectedTransferAmount',
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [1, 3, 5, 9, 10].map((amt) {
              final bool isSelected = _selectedTransferAmount == amt;
              return ChoiceChip(
                label: Text(
                  '+$amt',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.black : Colors.white70,
                  ),
                ),
                selected: isSelected,
                selectedColor: const Color(0xFF10B981),
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (val) {
                  if (val) setState(() => _selectedTransferAmount = amt);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // Botón de Enviar
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isTransferring ? null : _transferQueries,
              icon: _isTransferring
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : Icon(_isSubscribed ? Icons.send_rounded : Icons.lock_outline_rounded, size: 18),
              label: Text(
                _isSubscribed ? 'Enviar $_selectedTransferAmount Consultas a mi Amigo' : 'Desbloquear con Suscripción (\$0.99)',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSubscribed ? const Color(0xFF10B981) : const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
