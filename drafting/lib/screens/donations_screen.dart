import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/services/api_client.dart';
import '../core/services/iap_service.dart';
import '../core/services/language_service.dart';
import '../core/services/native_service.dart';

class DonationsScreen extends StatefulWidget {
  final VoidCallback onDataChanged;
  final bool isTab;

  const DonationsScreen({
    super.key,
    required this.onDataChanged,
    this.isTab = true,
  });

  @override
  State<DonationsScreen> createState() => _DonationsScreenState();
}

class _DonationsScreenState extends State<DonationsScreen> {
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _canEditProfile = false;
  String _selectedTierId = 'donate_25';

  List<dynamic> _tiers = [
    {'id': 'donate_10', 'name': 'Chispa Hextech', 'price_usd': 0.10, 'bonus_queries': 2, 'badge': 'Micro'},
    {'id': 'donate_25', 'name': 'Moneda Hextech', 'price_usd': 0.25, 'bonus_queries': 5, 'badge': 'Popular'},
    {'id': 'donate_49', 'name': 'Cristal de Apoyo', 'price_usd': 0.49, 'bonus_queries': 10, 'badge': 'Streamer'},
    {'id': 'donate_75', 'name': 'Orbe Challenger', 'price_usd': 0.75, 'bonus_queries': 15, 'badge': 'Destacado'},
    {'id': 'donate_99', 'name': 'Corona Leyenda', 'price_usd': 0.99, 'bonus_queries': 25, 'badge': 'Top VIP'},
  ];

  List<dynamic> _ranking = [];
  Map<String, dynamic>? _myDonorProfile;
  StreamSubscription<IapPurchaseResult>? _iapSub;

  @override
  void initState() {
    super.initState();
    _fetchRankingData();
    _listenIapResults();
  }

  void _listenIapResults() {
    InAppPurchaseService.instance.initialize();
    _iapSub = InAppPurchaseService.instance.onPurchaseResult.listen((res) async {
      if (!mounted) return;
      if (res.productId == null || InAppPurchaseService.donationIds.contains(res.productId)) {
        if (_isPurchasing) {
          setState(() => _isPurchasing = false);
        }
        if (res.success) {
          HapticFeedback.heavyImpact();
          widget.onDataChanged();
          await _fetchRankingData(silent: true);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Text(
                LanguageService.instance.tr('don_thanks_snack'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          );
          final bool hasChannelConfigured = _myDonorProfile != null &&
              (_myDonorProfile!['channel_url'] ?? '').toString().trim().isNotEmpty;
          if (!hasChannelConfigured && _canEditProfile && mounted) {
            _showEditChannelModal();
          }
        } else if (res.message != null && res.message!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              content: Text(res.message!),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _iapSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchRankingData({bool silent = false}) async {
    if (!silent && _ranking.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await ApiClient.get('/api/v1/donations/ranking', authenticated: true);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            if (data['tiers'] is List && (data['tiers'] as List).isNotEmpty) {
              _tiers = data['tiers'] as List<dynamic>;
            }
            _ranking = (data['ranking'] is List) ? data['ranking'] as List<dynamic> : [];
            _myDonorProfile = (data['my_donor_profile'] is Map<String, dynamic>)
                ? data['my_donor_profile'] as Map<String, dynamic>
                : null;
            _canEditProfile = data['can_edit_profile'] == true;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error cargando ranking de donadores: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startMicroDonation(String tierId) async {
    if (_isPurchasing) return;
    setState(() {
      _selectedTierId = tierId;
      _isPurchasing = true;
    });
    HapticFeedback.mediumImpact();

    final launched = await InAppPurchaseService.instance.buyPack(tierId);
    if (!launched && mounted) {
      setState(() => _isPurchasing = false);
    }
  }

  void _showEditChannelModal() {
    final lang = LanguageService.instance;
    if (!_canEditProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(
            lang.tr('don_locked_snack'),
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: (_myDonorProfile?['display_name'] ?? '').toString());
    final handleCtrl = TextEditingController(text: (_myDonorProfile?['channel_handle'] ?? '').toString());
    final urlCtrl = TextEditingController(text: (_myDonorProfile?['channel_url'] ?? '').toString());
    final bioCtrl = TextEditingController(text: (_myDonorProfile?['bio_message'] ?? '').toString());
    String selectedPlatform = (_myDonorProfile?['platform'] ?? 'tiktok').toString().toLowerCase();
    if (selectedPlatform != 'twitch' && selectedPlatform != 'kick' && selectedPlatform != 'tiktok') {
      selectedPlatform = 'tiktok';
    }
    bool isLive = _myDonorProfile?['is_live'] == true;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.live_tv_rounded, color: Color(0xFF00E5FF)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  lang.tr('don_modal_title'),
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      lang.tr('don_modal_platform_label'),
                      style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildPlatformSelectorChip(
                          label: 'TikTok',
                          platform: 'tiktok',
                          selected: selectedPlatform == 'tiktok',
                          color: const Color(0xFFFF0050),
                          onTap: () => setModalState(() => selectedPlatform = 'tiktok'),
                        ),
                        const SizedBox(width: 8),
                        _buildPlatformSelectorChip(
                          label: 'Twitch',
                          platform: 'twitch',
                          selected: selectedPlatform == 'twitch',
                          color: const Color(0xFF9146FF),
                          onTap: () => setModalState(() => selectedPlatform = 'twitch'),
                        ),
                        const SizedBox(width: 8),
                        _buildPlatformSelectorChip(
                          label: 'Kick',
                          platform: 'kick',
                          selected: selectedPlatform == 'kick',
                          color: const Color(0xFF53FC18),
                          onTap: () => setModalState(() => selectedPlatform = 'kick'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco(lang.tr('don_modal_name_hint')),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: handleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco(lang.tr('don_modal_handle_hint')),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: urlCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco(lang.tr('don_modal_url_hint')),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bioCtrl,
                      maxLength: 100,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco(lang.tr('don_modal_bio_hint')),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isLive
                            ? const Color(0xFFEF4444).withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isLive ? const Color(0xFFEF4444) : Colors.white12,
                        ),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: const Color(0xFFEF4444),
                        title: Text(
                          lang.tr('don_modal_live_title'),
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          lang.tr('don_modal_live_sub'),
                          style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
                        ),
                        value: isLive,
                        onChanged: (v) => setModalState(() => isLive = v),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: const Color(0xFF090D16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: saving
                            ? null
                            : () async {
                                setModalState(() => saving = true);
                                try {
                                  final res = await ApiClient.put(
                                    '/api/v1/donations/profile',
                                    authenticated: true,
                                    body: {
                                      'display_name': nameCtrl.text.trim(),
                                      'platform': selectedPlatform,
                                      'channel_handle': handleCtrl.text.trim(),
                                      'channel_url': urlCtrl.text.trim(),
                                      'bio_message': bioCtrl.text.trim(),
                                      'is_live': isLive,
                                    },
                                  );
                                  if (res.statusCode == 200) {
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    await _fetchRankingData();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(0xFF10B981),
                                          content: Text(lang.tr('don_modal_saved_snack')),
                                        ),
                                      );
                                    }
                                  } else {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: Colors.redAccent,
                                          content: Text(res.body),
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  debugPrint('Error guardando canal: $e');
                                }
                                if (ctx.mounted) setModalState(() => saving = false);
                              },
                        icon: const Icon(Icons.save_rounded, size: 19),
                        label: Text(
                          saving ? lang.tr('don_modal_saving') : lang.tr('don_modal_save_btn'),
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlatformSelectorChip({
    required String label,
    required String platform,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : Colors.white12,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? color : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      counterText: '',
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
    );
  }

  Color _platformAccent(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitch':
        return const Color(0xFF9146FF);
      case 'kick':
        return const Color(0xFF53FC18);
      default:
        return const Color(0xFFFF0050);
    }
  }

  String _platformName(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitch':
        return 'Twitch';
      case 'kick':
        return 'Kick';
      default:
        return 'TikTok';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        automaticallyImplyLeading: !widget.isTab,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.volunteer_activism_rounded, color: Color(0xFFFF0050), size: 22),
            const SizedBox(width: 8),
            Text(
              lang.tr('don_appbar'),
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF00E5FF), size: 24),
            tooltip: 'Configurar mi canal',
            onPressed: _showEditChannelModal,
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF080B11),
            ],
          ),
        ),
        child: RefreshIndicator(
          color: const Color(0xFF00E5FF),
          backgroundColor: const Color(0xFF0F172A),
          onRefresh: () => _fetchRankingData(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            children: [
              // 1. Cabecera: Micro-Donaciones estilo TikTok ($0.10 a $0.99)
              _buildMicroDonationsCard(),

              const SizedBox(height: 16),

              // 2. Botón para promocionar canal propio (Twitch, Kick o TikTok)
              _buildPromoteMyChannelBanner(),

              const SizedBox(height: 22),

              // 3. Ranking de Donadores en Vivo
              Row(
                children: [
                  const Icon(Icons.leaderboard_rounded, color: Color(0xFFC89B3C), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lang.tr('don_ranking_header'),
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: const Color(0xFFC89B3C),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                lang.tr('don_ranking_sub'),
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 12),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
                )
              else if (_ranking.isEmpty)
                _buildEmptyRankingCard()
              else
                ..._ranking.map((d) => _buildDonorRankingCard(d as Map<String, dynamic>)),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMicroDonationsCard() {
    Map<String, dynamic> currentTier = _tiers.firstWhere(
      (t) => (t as Map<String, dynamic>)['id'] == _selectedTierId,
      orElse: () => _tiers[1],
    ) as Map<String, dynamic>;

    final double priceUsd = (currentTier['price_usd'] is num)
        ? (currentTier['price_usd'] as num).toDouble()
        : 0.25;
    final int bonusQueries = (currentTier['bonus_queries'] is int)
        ? currentTier['bonus_queries'] as int
        : 5;
    final String displayPrice = InAppPurchaseService.instance.getDisplayPrice(
      _selectedTierId,
      '\$${priceUsd.toStringAsFixed(2)}',
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
        border: Border.all(color: const Color(0xFFFF0050).withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF0050).withValues(alpha: 0.14),
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
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF0050).withValues(alpha: 0.18),
                ),
                child: const Icon(Icons.favorite_rounded, color: Color(0xFFFF0050), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LanguageService.instance.tr('don_card_title'),
                      style: GoogleFonts.outfit(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      LanguageService.instance.tr('don_card_sub'),
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Selector horizontal de los 5 micro-montos ($0.10, $0.25, $0.49, $0.75, $0.99)
          Row(
            children: _tiers.map((raw) {
              final t = raw as Map<String, dynamic>;
              final String id = (t['id'] ?? '').toString();
              final double p = (t['price_usd'] is num) ? (t['price_usd'] as num).toDouble() : 0.10;
              final bool isSelected = id == _selectedTierId;
              final String chipPrice = InAppPurchaseService.instance.getDisplayPrice(
                id,
                '\$${p.toStringAsFixed(2)}',
              );

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedTierId = id);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFF0050).withValues(alpha: 0.24)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFF0050)
                              : Colors.white.withValues(alpha: 0.12),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              chipPrice,
                              style: GoogleFonts.outfit(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: isSelected ? Colors.white : Colors.white70,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '+${t['bonus_queries']}⚡',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? const Color(0xFF00E5FF) : Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF0050),
                foregroundColor: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isPurchasing ? null : () => _startMicroDonation(_selectedTierId),
              icon: _isPurchasing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.volunteer_activism_rounded, size: 20),
              label: Text(
                _isPurchasing
                    ? LanguageService.instance.tr('don_opening_play')
                    : LanguageService.instance.tr(
                        'don_btn_contribute',
                        {'price': displayPrice, 'queries': '$bonusQueries'},
                      ),
                style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoteMyChannelBanner() {
    final bool hasChannel = _myDonorProfile != null &&
        (_myDonorProfile!['channel_url'] ?? '').toString().trim().isNotEmpty;
    final bool isMyStreamLive = _myDonorProfile?['is_live'] == true;

    return InkWell(
      onTap: _showEditChannelModal,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF131C2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _canEditProfile
                ? const Color(0xFF00E5FF).withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasChannel ? Icons.live_tv_rounded : Icons.add_link_rounded,
              color: const Color(0xFF00E5FF),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasChannel
                        ? LanguageService.instance.tr(
                            'don_promote_my',
                            {
                              'name': '${_myDonorProfile!['display_name']}',
                              'platform': _platformName((_myDonorProfile!['platform'] ?? 'tiktok').toString()),
                            },
                          )
                        : LanguageService.instance.tr('don_promote_add'),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    hasChannel
                        ? (isMyStreamLive
                            ? LanguageService.instance.tr('don_promote_sub_live')
                            : LanguageService.instance.tr('don_promote_sub_edit'))
                        : (_canEditProfile
                            ? LanguageService.instance.tr('don_promote_sub_unlocked')
                            : LanguageService.instance.tr('don_promote_sub_locked')),
                    style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF00E5FF)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRankingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_outlined, color: Color(0xFFC89B3C), size: 42),
          const SizedBox(height: 10),
          Text(
            LanguageService.instance.tr('don_empty_title'),
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            LanguageService.instance.tr('don_empty_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  String _resolveDonorStreamUrl(String platform, String rawUrl, String handle) {
    String url = rawUrl.trim();
    final String cleanHandle = handle.trim().replaceFirst(RegExp(r'^@+'), '');
    if (url.isEmpty && cleanHandle.isNotEmpty) {
      switch (platform.toLowerCase()) {
        case 'twitch':
          return 'https://www.twitch.tv/$cleanHandle';
        case 'kick':
          return 'https://kick.com/$cleanHandle';
        default:
          return 'https://www.tiktok.com/@$cleanHandle';
      }
    }
    if (url.isNotEmpty &&
        !url.toLowerCase().startsWith('http://') &&
        !url.toLowerCase().startsWith('https://')) {
      url = 'https://${url.replaceFirst(RegExp(r'^/+'), '')}';
    }
    return url;
  }

  Widget _buildDonorRankingCard(Map<String, dynamic> donor) {
    final int rank = (donor['rank'] is int) ? donor['rank'] as int : 1;
    final String name = (donor['display_name'] ?? 'Donador').toString();
    final String platform = (donor['platform'] ?? 'tiktok').toString();
    final String handle = (donor['channel_handle'] ?? '').toString();
    final String rawUrl = (donor['channel_url'] ?? '').toString();
    final String url = _resolveDonorStreamUrl(platform, rawUrl, handle);
    final String bio = (donor['bio_message'] ?? '').toString();
    final bool isLive = donor['is_live'] == true;
    final double totalUsd = (donor['total_donated_usd'] is num)
        ? (donor['total_donated_usd'] as num).toDouble()
        : 0.0;

    final Color rankColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFE2E8F0)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : const Color(0xFF00E5FF);

    final Color pColor = _platformAccent(platform);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          if (url.isNotEmpty) {
            HapticFeedback.selectionClick();
            NativeService.openExternalUrl(url);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF1E293B),
                behavior: SnackBarBehavior.floating,
                content: Text(LanguageService.instance.tr('don_no_link_snack', {'name': name})),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLive
                  ? const Color(0xFFEF4444)
                  : (rank <= 3 ? rankColor.withValues(alpha: 0.55) : Colors.white12),
              width: isLive || rank == 1 ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Medalla de Posición (#1, #2, #3...)
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: rankColor.withValues(alpha: 0.16),
                  border: Border.all(color: rankColor.withValues(alpha: 0.6)),
                ),
                child: Text(
                  '#$rank',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: rankColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (isLive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              LanguageService.instance.tr('home_live_badge'),
                              style: GoogleFonts.outfit(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: pColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_platformName(platform)} ${handle.isNotEmpty ? "• $handle" : ""}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: pColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '\$${totalUsd.toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (url.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isLive
                              ? LanguageService.instance.tr('don_watch_stream')
                              : LanguageService.instance.tr('don_visit_channel'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isLive ? const Color(0xFFEF4444) : const Color(0xFF00E5FF),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 13,
                          color: isLive ? const Color(0xFFEF4444) : const Color(0xFF00E5FF),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

