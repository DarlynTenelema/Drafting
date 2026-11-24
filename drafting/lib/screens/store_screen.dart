import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/store_models.dart';
import '../core/services/ad_service.dart';
import '../core/services/api_client.dart';
import '../core/services/iap_service.dart';
import '../shared/mixins/localized_state_mixin.dart';
import '../shared/utils/app_snackbar.dart';
import '../theme/app_theme.dart';

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

class _StoreScreenState extends State<StoreScreen>
    with LocalizedStateMixin<StoreScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  // Modelo POO del catálogo y estado del usuario en la tienda
  StoreCatalog _catalog = const StoreCatalog();

  // Controladores para compartir consultas
  final TextEditingController _friendIdController = TextEditingController();
  int _selectedTransferAmount = 5;
  bool _isTransferring = false;
  bool _isPurchasing = false;
  bool _isWatchingAd = false;
  bool _isShowingCelebrationDialog = false;

  String? _watchingAdModel;

  Future<void> _watchRewardedAdForModel(String modelTier) async {
    if (_isWatchingAd) return;
    if (modelTier == 'flake' && _catalog.flakeAdsRemaining <= 0) return;
    if (modelTier == 'aureon' && _catalog.aureonAdsRemaining <= 0) return;

    setState(() {
      _isWatchingAd = true;
      _watchingAdModel = modelTier;
    });
    HapticFeedback.mediumImpact();

    await AdService.showRewardedAd(
      onUserEarnedReward: () async {
        try {
          final res = await ApiClient.post(
            '/api/v1/user/obtain-queries',
            authenticated: true,
            body: {'model_tier': modelTier},
          );
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final msg = (data['message'] ?? '¡Consultas añadidas con éxito!').toString();
            widget.onDataChanged();
            await _fetchCatalog(silent: true);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.hextechEmerald,
                  behavior: SnackBarBehavior.floating,
                  content: Text(msg),
                ),
              );
            }
          } else if (res.statusCode == 429) {
            String msg = 'Este modelo está en enfriamiento. Vuelve mañana.';
            try {
              final data = jsonDecode(res.body) as Map<String, dynamic>;
              if (data['message'] != null) msg = data['message'].toString();
            } catch (_) {}
            await _fetchCatalog(silent: true);
            if (mounted) _showErrorSnackBar(msg);
          }
        } catch (_) {}
        if (mounted) {
          setState(() {
            _isWatchingAd = false;
            _watchingAdModel = null;
          });
        }
      },
      onAdFailed: (error) {
        if (mounted) {
          setState(() {
            _isWatchingAd = false;
            _watchingAdModel = null;
          });
          _showErrorSnackBar(error);
        }
      },
    );
  }

  StreamSubscription<IapPurchaseResult>? _iapSubscription;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
    _initIap();
  }

  @override
  void onLanguageChanged() {
    _fetchCatalog(silent: true);
  }

  void _initIap() {
    InAppPurchaseService.instance.initialize();
    _iapSubscription = InAppPurchaseService.instance.onPurchaseResult.listen((result) {
      if (!mounted) return;
      // Ignorar eventos de micro-donaciones ya que son manejados exclusivamente por DonationsScreen
      if (result.productId != null && InAppPurchaseService.donationIds.contains(result.productId)) {
        return;
      }
      setState(() => _isPurchasing = false);

      if (result.success) {
        widget.onDataChanged();
        _fetchCatalog(silent: true);

        if (!result.alreadyProcessed && (result.queriesAdded > 0 || result.triviaLivesAdded > 0)) {
          HapticFeedback.heavyImpact();
          _showCelebrationDialog(
            title: result.triviaLivesAdded > 0
                ? tr('st_trivia_bought_title')
                : (result.isSubscription ? tr('st_sub_active_title') : tr('st_pack_bought_title')),
            message: result.message ?? tr('st_queries_credited'),
            queries: result.queriesAdded,
            triviaLives: result.triviaLivesAdded,
          );
        } else if (result.message != null && result.message!.isNotEmpty) {
          _showInfoSnackBar(result.message!);
        }
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

  Future<void> _fetchCatalog({bool silent = false}) async {
    if (!silent || (_catalog.packs.isEmpty && _catalog.subscriptions.isEmpty)) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await ApiClient.get('/api/v1/store/catalog', authenticated: true);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _catalog = StoreCatalog.fromJson(data);
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

  Future<void> _buyPack(StorePack pack) async {
    if (_isPurchasing) return;

    setState(() => _isPurchasing = true);
    HapticFeedback.mediumImpact();

    final launched = await InAppPurchaseService.instance.buyPack(pack.id);
    if (!launched && mounted) {
      setState(() => _isPurchasing = false);
    }
  }

  Future<void> _subscribe(SubscriptionPlan sub) async {
    if (_isPurchasing) return;

    if (_catalog.isSubscribed && _catalog.subscriptionPlan == sub.id) {
      _showInfoSnackBar(tr('st_already_sub_snack'));
      return;
    }

    setState(() => _isPurchasing = true);
    HapticFeedback.mediumImpact();

    final launched = await InAppPurchaseService.instance.buySubscription(sub.id);
    if (!launched && mounted) {
      setState(() => _isPurchasing = false);
    }
  }

  Future<void> _transferQueries() async {
    final rawTarget = _friendIdController.text.trim();
    if (rawTarget.isEmpty) {
      _showErrorSnackBar(tr('st_enter_friend_err'));
      return;
    }

    if (!_catalog.canTransfer) {
      _showSubscriptionRequiredDialog();
      return;
    }

    if (_catalog.remainingTransferQuota <= 0) {
      _showErrorSnackBar(tr('st_limit_reached_err'));
      return;
    }

    if (_selectedTransferAmount > _catalog.remainingTransferQuota) {
      _showErrorSnackBar(tr('st_quota_left_err', {'left': '${_catalog.remainingTransferQuota}'}));
      return;
    }

    if (_selectedTransferAmount > (_catalog.availableQueries + _catalog.giftQueries)) {
      _showErrorSnackBar(tr('st_not_enough_err', {'amount': '$_selectedTransferAmount'}));
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
          AppSnackBar.showSuccess(
            context,
            data['message'] ?? tr('st_transfer_ok'),
            icon: Icons.check_circle_rounded,
            useOutfitFont: true,
          );
        }
      } else {
        final errorMsg = response.body.isNotEmpty ? response.body : tr('net_error');
        _showErrorSnackBar(errorMsg);
      }
    } catch (e) {
      _showErrorSnackBar(tr('net_error'));
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  void _showErrorSnackBar(String message) {
    AppSnackBar.showError(context, message);
  }

  void _showInfoSnackBar(String message) {
    AppSnackBar.showInfo(context, message);
  }

  void _showCelebrationDialog({
    required String title,
    required String message,
    int queries = 0,
    int triviaLives = 0,
  }) {
    if (!mounted || _isShowingCelebrationDialog) return;
    _isShowingCelebrationDialog = true;
    final bool isLives = triviaLives > 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isLives ? AppTheme.hextechCrimson : AppTheme.hextechGold,
            width: 1.5,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isLives ? AppTheme.hextechCrimson : AppTheme.hextechGold).withValues(alpha: 0.15),
              ),
              child: Icon(
                isLives ? Icons.favorite_rounded : Icons.bolt_rounded,
                size: 48,
                color: isLives ? AppTheme.hextechCrimson : AppTheme.hextechCyan,
              ),
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
                color: (isLives ? AppTheme.hextechCrimson : AppTheme.hextechEmerald).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isLives
                    ? tr('st_trivia_lives_badge', {'count': '$triviaLives'})
                    : tr('st_queries_ready_badge', {'count': '$queries'}),
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isLives ? AppTheme.hextechCrimson : AppTheme.hextechEmerald,
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
                  backgroundColor: isLives ? AppTheme.hextechCrimson : AppTheme.hextechGold,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  tr('st_to_ranked_btn'),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      _isShowingCelebrationDialog = false;
    });
  }

  void _showSubscriptionRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppTheme.hextechCyan, width: 1.5),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_person_rounded, size: 44, color: AppTheme.hextechCyan),
            const SizedBox(height: 14),
            Text(
              tr('st_share_modal_title'),
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('st_share_modal_body'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.hextechCyan,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(tr('st_share_modal_btn')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queryPacks = _catalog.queryPacks;
    final triviaPacks = _catalog.triviaPacks;

    return Scaffold(
      backgroundColor: AppTheme.deepDarkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        automaticallyImplyLeading: !widget.isTab,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_rounded, color: AppTheme.hextechGold, size: 22),
            const SizedBox(width: 8),
            Text(
              tr('st_appbar'),
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
            tooltip: tr('st_restore_tooltip'),
            onPressed: () async {
              AppSnackBar.showInfo(
                context,
                tr('st_restoring_snack'),
                hideCurrent: false,
                icon: null,
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
              child: CircularProgressIndicator(color: AppTheme.hextechCyan),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppTheme.hextechCrimson, size: 48),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchCatalog,
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.hextechCyan),
                          child: Text(tr('st_retry'), style: const TextStyle(color: Colors.black)),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchCatalog,
                  color: AppTheme.hextechCyan,
                  backgroundColor: AppTheme.background,
                  child: ListView(
                    padding: const EdgeInsets.only(left: 18, right: 18, top: 16, bottom: 100),
                    children: [
                      // --- TARJETA DE SALDO Y ESTADO ACTUAL ---
                      _buildUserStatusCard(),

                      const SizedBox(height: 18),

                      // --- TARJETA DE RECARGA GRATIS CON VIDEO POR MODELO ---
                      _buildModelAdsRechargeCard(),

                      const SizedBox(height: 20),

                      // --- 1. PAQUETES DE CONSULTAS (COMPRAS ÚNICAS) ---
                      _buildSectionHeader(
                        title: tr('st_packs_header'),
                        subtitle: tr('st_packs_sub'),
                        icon: Icons.all_inclusive_rounded,
                        color: AppTheme.hextechCyan,
                      ),
                      const SizedBox(height: 14),

                      // Tarjetas de Paquetes de Consultas
                      ...queryPacks.map(_buildPackCard),

                      // --- 1.5 PAQUETES DE VIDAS PARA TRIVIA ---
                      if (triviaPacks.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _buildSectionHeader(
                          title: tr('st_trivia_packs_header'),
                          subtitle: tr('st_trivia_packs_sub'),
                          icon: Icons.favorite_rounded,
                          color: AppTheme.hextechCrimson,
                        ),
                        const SizedBox(height: 14),
                        ...triviaPacks.map(_buildPackCard),
                      ],

                      // --- 2. SUSCRIPCIONES MENSUALES (Ocultas cuando el catálogo no envía suscripciones) ---
                      if (_catalog.subscriptions.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _buildSectionHeader(
                          title: tr('st_subs_header'),
                          subtitle: tr('st_subs_sub'),
                          icon: Icons.workspace_premium_rounded,
                          color: AppTheme.hextechGold,
                        ),
                        const SizedBox(height: 14),

                        // Tarjetas de Suscripciones
                        ..._catalog.subscriptions.map(_buildSubscriptionCard),
                      ],

                      const SizedBox(height: 28),

                      // --- 3. SISTEMA VIRAL: COMPARTIR CON TU DÚO ---
                      _buildShareQueriesCard(),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildModelAdsRechargeCard() {
    Widget buildAdRow({
      required String modelTier,
      required String title,
      required String subtitle,
      required Color accent,
      required bool onCooldown,
    }) {
      final bool isBusy = _isWatchingAd && _watchingAdModel == modelTier;
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.storeCardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: onCooldown ? Colors.white12 : accent.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(
              onCooldown ? Icons.hourglass_bottom_rounded : Icons.play_circle_fill_rounded,
              color: onCooldown ? Colors.white38 : accent,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_isWatchingAd || onCooldown)
                  ? null
                  : () => _watchRewardedAdForModel(modelTier),
              style: ElevatedButton.styleFrom(
                backgroundColor: onCooldown ? Colors.white10 : accent,
                disabledBackgroundColor: Colors.white10,
                foregroundColor: onCooldown ? Colors.white54 : Colors.black,
                disabledForegroundColor: Colors.white54,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      onCooldown ? 'Enfriamiento' : 'Ver Video',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            AppTheme.hextechEmerald.withValues(alpha: 0.14),
            AppTheme.background,
          ],
        ),
        border: Border.all(color: AppTheme.hextechEmerald.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.ondemand_video_rounded, color: AppTheme.hextechEmerald, size: 20),
              const SizedBox(width: 8),
              Text(
                'Recargar consultas con anuncios',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          buildAdRow(
            modelTier: 'classic',
            title: 'Classic (+2 consultas)',
            subtitle: 'Disponible por video • Sin límite diario',
            accent: AppTheme.hextechCyan,
            onCooldown: false,
          ),
          buildAdRow(
            modelTier: 'flake',
            title: 'Flake 1.0 (+1 consulta)',
            subtitle: _catalog.flakeAdsRemaining > 0
                ? 'Te quedan ${_catalog.flakeAdsRemaining}/2 videos hoy'
                : 'Límite diario alcanzado (2/2) • Vuelve mañana',
            accent: AppTheme.hextechGold,
            onCooldown: _catalog.flakeAdsRemaining <= 0,
          ),
          buildAdRow(
            modelTier: 'aureon',
            title: 'Aureon 1.0 (+1 consulta)',
            subtitle: _catalog.aureonAdsRemaining > 0
                ? 'Te queda ${_catalog.aureonAdsRemaining}/1 video hoy'
                : 'Límite diario alcanzado (1/1) • Vuelve mañana',
            accent: const Color(0xFFC4B5FD),
            onCooldown: _catalog.aureonAdsRemaining <= 0,
          ),
        ],
      ),
    );
  }

  Widget _buildUserStatusCard() {
    Widget buildWalletPill(String label, int count, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppTheme.surface, AppTheme.background],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppTheme.hextechCyan.withValues(alpha: 0.25)),
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
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.hextechCyan.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.bolt_rounded, color: AppTheme.hextechCyan, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'Tus consultas por modelo',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              buildWalletPill('CLASSIC', _catalog.classicQueries, AppTheme.hextechCyan),
              const SizedBox(width: 8),
              buildWalletPill('FLAKE 1.0', _catalog.flakeQueries, AppTheme.hextechGold),
              const SizedBox(width: 8),
              buildWalletPill('AUREON 1.0', _catalog.aureonQueries, const Color(0xFFC4B5FD)),
            ],
          ),
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

  Widget _buildPackCard(StorePack pack) {
    final Color tagTextColor = pack.tagTextColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.storeCardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pack.borderColor),
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
                    pack.icon,
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
                              pack.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (pack.tag.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: pack.tagBgColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                pack.tag.toUpperCase(),
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
                            pack.isTrivia
                                ? '${pack.triviaLives} Vidas ❤️'
                                : tr('st_pack_queries', {'count': '${pack.queries}'}),
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: pack.isTrivia ? AppTheme.hextechCrimson : AppTheme.hextechCyan,
                            ),
                          ),
                          if (pack.bonusQueries > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              tr('st_pack_bonus', {'bonus': '${pack.bonusQueries}'}),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.hextechEmerald,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pack.description,
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _isPurchasing ? null : () => _buyPack(pack),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pack.buttonBgColor,
                    foregroundColor: pack.buttonFgColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    InAppPurchaseService.instance.getDisplayPrice(
                      pack.id,
                      pack.formattedFallbackPrice,
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

  Widget _buildSubscriptionCard(SubscriptionPlan sub) {
    final bool isCurrentPlan = _catalog.isSubscribed && _catalog.subscriptionPlan == sub.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.storeCardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentPlan ? AppTheme.hextechGold : AppTheme.hextechGold.withValues(alpha: 0.25),
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
                    color: AppTheme.hextechGold.withValues(alpha: 0.15),
                    border: Border.all(color: AppTheme.hextechGold.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    sub.icon,
                    color: AppTheme.hextechGold,
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
                              sub.name,
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
                              color: AppTheme.hextechGold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sub.tag,
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.hextechGold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr('st_sub_queries_month', {'count': '${sub.queriesPerMonth}'}),
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.hextechGold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sub.description,
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _isPurchasing ? null : () => _subscribe(sub),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCurrentPlan ? AppTheme.hextechEmerald : AppTheme.hextechGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isCurrentPlan
                        ? tr('st_active')
                        : InAppPurchaseService.instance.getDisplayPrice(
                            sub.id,
                            sub.fallbackPriceWithSuffix(tr('st_sub_per_month')),
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
    final myReferralCode = _catalog.myReferralCode;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.storeCardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _catalog.isSubscribed
              ? AppTheme.hextechEmerald.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
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
                  color: AppTheme.hextechEmerald.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.share_rounded, color: AppTheme.hextechEmerald, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('st_share_header'),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      tr('st_share_sub'),
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
                  tr('st_quota_today_label'),
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                ),
                Text(
                  tr(
                    'st_quota_today_val',
                    {
                      'sent': '${_catalog.dailyTransferredToday}',
                      'left': '${_catalog.remainingTransferQuota}',
                    },
                  ),
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _catalog.canTransfer ? AppTheme.hextechEmerald : Colors.amberAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tu propio ID para recibir consultas
          if (myReferralCode != null && myReferralCode.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.hextechCyan.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.badge_rounded, color: AppTheme.hextechCyan, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('st_your_id_label'),
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
                        ),
                        Text(
                          myReferralCode,
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.hextechCyan),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
                    tooltip: tr('st_copy_id_tooltip'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: myReferralCode));
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppTheme.hextechEmerald,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          content: Text(tr('st_id_copied_snack')),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (_catalog.giftQueries > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.hextechEmerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.hextechEmerald.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded, color: AppTheme.hextechEmerald, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('st_gift_queries_banner', {'count': '${_catalog.giftQueries}'}),
                      style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.hextechEmerald, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Campo: ID del Jugador
          Text(
            tr('st_friend_id_label'),
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _friendIdController,
            textCapitalization: TextCapitalization.characters,
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: tr('st_friend_id_hint'),
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              filled: true,
              fillColor: AppTheme.background,
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
                borderSide: const BorderSide(color: AppTheme.hextechCyan),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Selector de cantidad de consultas (1 a 10)
          Text(
            tr('st_transfer_amount_label', {'amount': '$_selectedTransferAmount'}),
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
                selectedColor: AppTheme.hextechEmerald,
                backgroundColor: AppTheme.background,
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
                  : Icon(_catalog.canTransfer ? Icons.send_rounded : Icons.lock_outline_rounded, size: 18),
              label: Text(
                _catalog.canTransfer
                    ? tr('st_send_btn_unlocked', {'amount': '$_selectedTransferAmount'})
                    : tr('st_send_btn_locked'),
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _catalog.canTransfer ? AppTheme.hextechEmerald : AppTheme.hextechCyan,
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
