import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/donation_models.dart';
import '../core/models/social_platform.dart';
import '../core/services/api_client.dart';
import '../core/services/iap_service.dart';
import '../core/services/native_service.dart';
import '../shared/mixins/localized_state_mixin.dart';
import '../shared/widgets/hextech_ui.dart';
import '../theme/app_theme.dart';

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

class _DonationsScreenState extends State<DonationsScreen>
    with LocalizedStateMixin<DonationsScreen> {
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _canEditProfile = false;
  String _selectedTierId = 'donate_25';

  List<DonationTier> _tiers = DonationTier.defaultTiers;
  List<DonorProfile> _ranking = [];
  DonorProfile? _myDonorProfile;
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
              backgroundColor: AppTheme.hextechEmerald,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Text(
                tr('don_thanks_snack'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          );
          final bool hasChannelConfigured =
              _myDonorProfile != null && _myDonorProfile!.hasChannelConfigured;
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
              _tiers = (data['tiers'] as List<dynamic>)
                  .whereType<Map<String, dynamic>>()
                  .map(DonationTier.fromJson)
                  .toList();
            }
            _ranking = (data['ranking'] is List)
                ? (data['ranking'] as List<dynamic>)
                    .whereType<Map<String, dynamic>>()
                    .map(DonorProfile.fromJson)
                    .toList()
                : [];
            _myDonorProfile = (data['my_donor_profile'] is Map<String, dynamic>)
                ? DonorProfile.fromJson(data['my_donor_profile'] as Map<String, dynamic>)
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
    if (!_canEditProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.hextechAmber,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(
            tr('don_locked_snack'),
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController(text: _myDonorProfile?.displayName ?? '');
    final handleCtrl = TextEditingController(text: _myDonorProfile?.channelHandle ?? '');
    final urlCtrl = TextEditingController(text: _myDonorProfile?.channelUrl ?? '');
    final bioCtrl = TextEditingController(text: _myDonorProfile?.bioMessage ?? '');
    String selectedPlatform = (_myDonorProfile?.platform ?? 'tiktok').toLowerCase();
    if (selectedPlatform != 'twitch' && selectedPlatform != 'kick' && selectedPlatform != 'tiktok') {
      selectedPlatform = 'tiktok';
    }
    bool isLive = _myDonorProfile?.isLive == true;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
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
                              const Icon(Icons.live_tv_rounded, color: AppTheme.hextechCyan),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tr('don_modal_title'),
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
                      tr('don_modal_platform_label'),
                      style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildPlatformSelectorChip(
                          label: 'TikTok',
                          selected: selectedPlatform == 'tiktok',
                          color: AppTheme.hextechPink,
                          onTap: () => setModalState(() => selectedPlatform = 'tiktok'),
                        ),
                        const SizedBox(width: 8),
                        _buildPlatformSelectorChip(
                          label: 'Twitch',
                          selected: selectedPlatform == 'twitch',
                          color: const Color(0xFF9146FF),
                          onTap: () => setModalState(() => selectedPlatform = 'twitch'),
                        ),
                        const SizedBox(width: 8),
                        _buildPlatformSelectorChip(
                          label: 'Kick',
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
                      decoration: AppTheme.hextechInputDecoration(
                        hintText: tr('don_modal_name_hint'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: handleCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: AppTheme.hextechInputDecoration(
                        hintText: tr('don_modal_handle_hint'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: urlCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: AppTheme.hextechInputDecoration(
                        hintText: tr('don_modal_url_hint'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bioCtrl,
                      maxLength: 100,
                      style: const TextStyle(color: Colors.white),
                      decoration: AppTheme.hextechInputDecoration(
                        hintText: tr('don_modal_bio_hint'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isLive
                            ? AppTheme.hextechCrimson.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isLive ? AppTheme.hextechCrimson : Colors.white12,
                        ),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppTheme.hextechCrimson,
                        title: Text(
                          tr('don_modal_live_title'),
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          tr('don_modal_live_sub'),
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
                          backgroundColor: AppTheme.hextechCyan,
                          foregroundColor: AppTheme.deepDarkBg,
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
                                          backgroundColor: AppTheme.hextechEmerald,
                                          content: Text(tr('don_modal_saved_snack')),
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
                          saving ? tr('don_modal_saving') : tr('don_modal_save_btn'),
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
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return HextechSelectableChip(
      label: label,
      selected: selected,
      activeColor: color,
      padding: const EdgeInsets.symmetric(vertical: 10),
      borderRadius: 12,
      textStyle: GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: selected ? color : Colors.white70,
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkScaffold,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        automaticallyImplyLeading: !widget.isTab,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.volunteer_activism_rounded, color: AppTheme.hextechPink, size: 22),
            const SizedBox(width: 8),
            Text(
              tr('don_appbar'),
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
            icon: const Icon(Icons.edit_note_rounded, color: AppTheme.hextechCyan, size: 24),
            tooltip: 'Configurar mi canal',
            onPressed: _showEditChannelModal,
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppTheme.screenBackgroundGradient,
        ),
        child: RefreshIndicator(
          color: AppTheme.hextechCyan,
          backgroundColor: AppTheme.background,
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
                  const Icon(Icons.leaderboard_rounded, color: AppTheme.hextechGold, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('don_ranking_header'),
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppTheme.hextechGold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                tr('don_ranking_sub'),
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 12),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator(color: AppTheme.hextechCyan)),
                )
              else if (_ranking.isEmpty)
                _buildEmptyRankingCard()
              else
                ..._ranking.map(_buildDonorRankingCard),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMicroDonationsCard() {
    final DonationTier currentTier = _tiers.firstWhere(
      (t) => t.id == _selectedTierId,
      orElse: () => _tiers.length > 1 ? _tiers[1] : _tiers.first,
    );

    final String displayPrice = InAppPurchaseService.instance.getDisplayPrice(
      _selectedTierId,
      currentTier.formattedFallbackPrice,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surface,
            AppTheme.background,
          ],
        ),
        border: Border.all(color: AppTheme.hextechPink.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.hextechPink.withValues(alpha: 0.14),
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
                  color: AppTheme.hextechPink.withValues(alpha: 0.18),
                ),
                child: const Icon(Icons.favorite_rounded, color: AppTheme.hextechPink, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('don_card_title'),
                      style: GoogleFonts.outfit(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      tr('don_card_sub'),
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
            children: _tiers.map((t) {
              final bool isSelected = t.id == _selectedTierId;
              final String chipPrice = InAppPurchaseService.instance.getDisplayPrice(
                t.id,
                t.formattedFallbackPrice,
              );

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedTierId = t.id);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.hextechPink.withValues(alpha: 0.24)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.hextechPink
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
                            '+${t.bonusQueries}⚡',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? AppTheme.hextechCyan : Colors.white38,
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
                backgroundColor: AppTheme.hextechPink,
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
                    ? tr('don_opening_play')
                    : tr(
                        'don_btn_contribute',
                        {'price': displayPrice, 'queries': '${currentTier.bonusQueries}'},
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
    final bool hasChannel = _myDonorProfile != null && _myDonorProfile!.hasChannelConfigured;
    final bool isMyStreamLive = _myDonorProfile?.isLive == true;

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
                ? AppTheme.hextechCyan.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasChannel ? Icons.live_tv_rounded : Icons.add_link_rounded,
              color: AppTheme.hextechCyan,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasChannel
                        ? tr(
                            'don_promote_my',
                            {
                              'name': _myDonorProfile!.displayName,
                              'platform': _myDonorProfile!.socialPlatform.creatorPlatformName,
                            },
                          )
                        : tr('don_promote_add'),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    hasChannel
                        ? (isMyStreamLive
                            ? tr('don_promote_sub_live')
                            : tr('don_promote_sub_edit'))
                        : (_canEditProfile
                            ? tr('don_promote_sub_unlocked')
                            : tr('don_promote_sub_locked')),
                    style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.hextechCyan),
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
          const Icon(Icons.emoji_events_outlined, color: AppTheme.hextechGold, size: 42),
          const SizedBox(height: 10),
          Text(
            tr('don_empty_title'),
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('don_empty_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildDonorRankingCard(DonorProfile donor) {
    final SocialPlatform social = donor.socialPlatform;
    final String url = donor.resolvedStreamUrl;
    final Color rankColor = donor.rankColor;
    final Color pColor = social.creatorAccentColor;

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
                backgroundColor: AppTheme.surface,
                behavior: SnackBarBehavior.floating,
                content: Text(tr('don_no_link_snack', {'name': donor.displayName})),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: donor.isLive
                  ? AppTheme.hextechCrimson
                  : (donor.rank <= 3 ? rankColor.withValues(alpha: 0.55) : Colors.white12),
              width: donor.isLive || donor.rank == 1 ? 1.4 : 1.0,
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
                  '#${donor.rank}',
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
                            donor.displayName,
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
                        if (donor.isLive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.hextechCrimson,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tr('home_live_badge'),
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
                            '${social.creatorPlatformName} ${donor.channelHandle.isNotEmpty ? "• ${donor.channelHandle}" : ""}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: pColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (donor.bioMessage.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        donor.bioMessage,
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
                      color: AppTheme.hextechEmerald.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '\$${donor.totalDonatedUsd.toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.hextechEmerald,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (url.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          donor.isLive
                              ? tr('don_watch_stream')
                              : tr('don_visit_channel'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: donor.isLive ? AppTheme.hextechCrimson : AppTheme.hextechCyan,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 13,
                          color: donor.isLive ? AppTheme.hextechCrimson : AppTheme.hextechCyan,
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
