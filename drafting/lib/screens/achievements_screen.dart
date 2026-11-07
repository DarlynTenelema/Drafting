import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/services/api_client.dart';
import '../core/services/language_service.dart';
import '../core/services/session_service.dart';

class AchievementsScreen extends StatefulWidget {
  final String referralCode;
  final int referralCount;
  final int referralRewardsClaimed;
  final bool hasRedeemedReferral;
  final VoidCallback onDataChanged;
  final bool isTab;

  const AchievementsScreen({
    super.key,
    required this.referralCode,
    required this.referralCount,
    required this.referralRewardsClaimed,
    required this.hasRedeemedReferral,
    required this.onDataChanged,
    this.isTab = false,
  });

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isRedeeming = false;
  String? _errorMessage;
  String? _successMessage;

  late int _count;
  late int _claimed;
  late bool _hasRedeemed;

  @override
  void initState() {
    super.initState();
    _count = widget.referralCount;
    _claimed = widget.referralRewardsClaimed;
    _hasRedeemed = widget.hasRedeemedReferral;
    LanguageService.instance.languageNotifier.addListener(_onLanguageChanged);
    _checkClipboardForCode();
  }

  void _onLanguageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant AchievementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.referralCount != widget.referralCount ||
        oldWidget.referralRewardsClaimed != widget.referralRewardsClaimed ||
        oldWidget.hasRedeemedReferral != widget.hasRedeemedReferral) {
      setState(() {
        _count = widget.referralCount;
        _claimed = widget.referralRewardsClaimed;
        _hasRedeemed = widget.hasRedeemedReferral;
      });
    }
  }

  String _extractReferralCode(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return '';
    // Si el usuario pegó un mensaje de WhatsApp/Discord que incluye el código WRxxxxxx
    final match = RegExp(r'\b(WR[A-Z0-9]{4,10})\b', caseSensitive: false).firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.toUpperCase();
    }
    return trimmed.replaceAll('#', '').replaceAll('@', '').trim().toUpperCase();
  }

  Future<void> _checkClipboardForCode() async {
    if (_hasRedeemed) return;
    try {
      final data = await Clipboard.getData('text/plain');
      final rawText = data?.text?.trim();
      if (rawText != null && rawText.isNotEmpty) {
        final extracted = _extractReferralCode(rawText);
        if (extracted.startsWith('WR') &&
            extracted.length >= 6 &&
            extracted.length <= 10 &&
            extracted != widget.referralCode.toUpperCase()) {
          if (mounted && _codeController.text.isEmpty) {
            setState(() {
              _codeController.text = extracted;
            });
          }
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    LanguageService.instance.languageNotifier.removeListener(_onLanguageChanged);
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _redeemCode() async {
    final lang = LanguageService.instance;
    final code = _extractReferralCode(_codeController.text);
    if (code.isEmpty) {
      setState(() {
        _errorMessage = lang.tr('ach_enter_code_err');
      });
      return;
    }

    setState(() {
      _isRedeeming = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final deviceId = await SessionService.getDeviceId();
      final response = await ApiClient.post(
        '/api/v1/user/redeem-referral',
        authenticated: true,
        body: {
          'referral_code': code,
          'device_id': deviceId,
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _successMessage = data['message'] ?? lang.tr('ach_redeem_ok');
          _hasRedeemed = true;
          _codeController.clear();
        });
        widget.onDataChanged();
      } else {
        setState(() {
          _errorMessage = response.body.replaceAll('"', '').trim();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = lang.tr('ach_net_err');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRedeeming = false;
        });
      }
    }
  }

  void _copyToClipboard(String text, {bool isFullMessage = false}) {
    final lang = LanguageService.instance;
    final toCopy = isFullMessage
        ? lang.tr('ach_invite_msg', {'code': text})
        : text;
    Clipboard.setData(ClipboardData(text: toCopy));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(isFullMessage ? lang.tr('ach_msg_copied') : lang.tr('ach_code_copied')),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.instance;
    final int currentFriends = _count.clamp(0, 10);
    final int friendsNeeded = (10 - currentFriends).clamp(0, 10);
    final bool isMaxedOut = currentFriends >= 10 || _claimed >= 10;
    final int earnedQueries = currentFriends * 5;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        automaticallyImplyLeading: !widget.isTab,
        leading: widget.isTab
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, color: Color(0xFF10B981), size: 22),
            const SizedBox(width: 8),
            Text(
              lang.tr('ach_appbar'),
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
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: lang.tr('ach_refresh_tooltip'),
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onDataChanged();
            },
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
        child: SafeArea(
          child: RefreshIndicator(
            color: const Color(0xFF10B981),
            backgroundColor: const Color(0xFF0F172A),
            onRefresh: () async {
              widget.onDataChanged();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. HERO CARD: LOGRO PRINCIPAL
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF10B981).withValues(alpha: 0.18),
                          const Color(0xFF0F172A),
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          blurRadius: 20,
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
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF10B981),
                              ),
                              child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lang.tr('ach_hero_title'),
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    lang.tr('ach_hero_sub'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF10B981)),
                              ),
                              child: Text(
                                '$currentFriends/10',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (currentFriends / 10).clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                            minHeight: 10,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                isMaxedOut
                                    ? lang.tr('ach_maxed')
                                    : lang.tr('ach_progress', {'earned': '$earnedQueries', 'needed': '$friendsNeeded'}),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isMaxedOut ? const Color(0xFF10B981) : Colors.white70,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              lang.tr('ach_friends_count', {'count': '$currentFriends'}),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 5 Hitos con Íconos Gamificados (2, 4, 6, 8, 10 amigos)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(5, (index) {
                            final tier = index + 1;
                            final reqFriends = tier * 2;
                            final isClaimed = currentFriends >= reqFriends;
                            final isCurrent = currentFriends < reqFriends && currentFriends >= (reqFriends - 2);

                            Color iconColor = Colors.white24;
                            Color bgColor = Colors.white.withValues(alpha: 0.04);
                            Color borderColor = Colors.white.withValues(alpha: 0.08);

                            if (isClaimed) {
                              iconColor = const Color(0xFF10B981);
                              bgColor = const Color(0xFF10B981).withValues(alpha: 0.15);
                              borderColor = const Color(0xFF10B981).withValues(alpha: 0.4);
                            } else if (isCurrent) {
                              iconColor = const Color(0xFF00E5FF);
                              bgColor = const Color(0xFF00E5FF).withValues(alpha: 0.15);
                              borderColor = const Color(0xFF00E5FF).withValues(alpha: 0.5);
                            }

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: bgColor,
                                    border: Border.all(color: borderColor, width: isCurrent ? 1.5 : 1.0),
                                    boxShadow: isCurrent || isClaimed
                                        ? [
                                            BoxShadow(
                                              color: iconColor.withValues(alpha: 0.25),
                                              blurRadius: 8,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Icon(
                                      isClaimed
                                          ? Icons.check_circle_rounded
                                          : isCurrent
                                              ? Icons.stars_rounded
                                              : Icons.lock_outline_rounded,
                                      color: iconColor,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.group_rounded, size: 10, color: Colors.white54),
                                    const SizedBox(width: 2),
                                    Text(
                                      '$reqFriends',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isClaimed || isCurrent ? Colors.white : Colors.white38,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // 2. TU CÓDIGO DE INVITACIÓN
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.share_rounded, color: Color(0xFF00E5FF), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            lang.tr('ach_share_title'),
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        lang.tr('ach_share_sub'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.referralCode.isNotEmpty ? widget.referralCode : lang.tr('ach_generating'),
                                style: GoogleFonts.outfit(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.5,
                                  color: const Color(0xFF00E5FF),
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E5FF),
                                foregroundColor: Colors.black,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: widget.referralCode.isNotEmpty
                                  ? () => _copyToClipboard(widget.referralCode)
                                  : null,
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: Text(lang.tr('ach_copy_btn'), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00E5FF),
                            side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: widget.referralCode.isNotEmpty
                              ? () => _copyToClipboard(widget.referralCode, isFullMessage: true)
                              : null,
                          icon: const Icon(Icons.share_rounded, size: 16),
                          label: Text(
                            lang.tr('ach_share_msg_btn'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 3. CANJEAR CÓDIGO DE UN AMIGO
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.card_giftcard_rounded, color: Color(0xFFF59E0B), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            lang.tr('ach_redeem_title'),
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        lang.tr('ach_redeem_sub'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 14),

                      if (_hasRedeemed)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  lang.tr('ach_already_redeemed'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _codeController,
                                textCapitalization: TextCapitalization.characters,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  hintText: lang.tr('ach_code_hint'),
                                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isRedeeming ? null : _redeemCode,
                              child: _isRedeeming
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(lang.tr('ach_redeem_btn'), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ],
                        if (_successMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _successMessage!,
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 4. PRÓXIMOS LOGROS (ROADMAP / GAMIFICACIÓN FUTURA)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    lang.tr('ach_upcoming_header'),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildUpcomingAchievement(lang.tr('ach_up1_title'), lang.tr('ach_up1_sub'), Icons.local_fire_department_rounded),
                const SizedBox(height: 10),
                _buildUpcomingAchievement(lang.tr('ach_up2_title'), lang.tr('ach_up2_sub'), Icons.shield_rounded),
                const SizedBox(height: 100),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingAchievement(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white38, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              LanguageService.instance.tr('ach_soon'),
              style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
