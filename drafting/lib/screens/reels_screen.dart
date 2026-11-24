import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../core/services/api_client.dart';
import '../core/services/language_service.dart';
import '../core/services/native_service.dart';
import '../core/services/reels_service.dart';
import '../shared/mixins/localized_state_mixin.dart';
import '../shared/utils/app_snackbar.dart';
import '../theme/app_theme.dart';

class ReelsScreen extends StatefulWidget {
  final bool isTab;
  final bool isActive;
  final String? userPhotoUrl;

  const ReelsScreen({
    super.key,
    this.isTab = true,
    this.isActive = true,
    this.userPhotoUrl,
  });

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen>
    with WidgetsBindingObserver, LocalizedStateMixin<ReelsScreen> {
  late PageController _pageController;
  final List<ReelModel> _reels = [];
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<String, String> _viewTokens = {};
  final Set<String> _verifiedViewsSent = {};
  final Map<String, int> _watchedAccumulatedMs = {};
  final Map<String, int> _lastObservedPosMs = {};
  final Map<int, VoidCallback> _progressListeners = {};

  int _currentIndex = 0;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isLoadingMore = false;
  bool _isOpeningLandscape = false;
  String? _nextCursor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _fetchReels();
  }

  @override
  void didUpdateWidget(covariant ReelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      // Pausar reproducción inmediatamente al cambiar de pestaña en IndexedStack
      _controllers[_currentIndex]?.pause();
      _restorePortraitOrientation();
    } else if (!oldWidget.isActive && widget.isActive) {
      final ctrl = _controllers[_currentIndex];
      if (ctrl != null && ctrl.value.isInitialized) {
        ctrl.play();
        _startVerifiedViewTracking(_currentIndex, ctrl);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restorePortraitOrientation();
    _pageController.dispose();
    _disposeAllControllers();
    super.dispose();
  }

  void _restorePortraitOrientation() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _syncAllowedOrientationsForIndex(int index) {
    if (!widget.isActive || index < 0 || index >= _reels.length) {
      _restorePortraitOrientation();
      return;
    }
    final reel = _reels[index];
    final ctrl = _controllers[index];
    final isLandscapeVideo = _isControllerLandscape(ctrl, reel);
    if (isLandscapeVideo) {
      // Permitir giro físico automático del teléfono cuando el video es horizontal
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  bool _isControllerLandscape(VideoPlayerController? c, ReelModel reel) {
    if (c != null && c.value.isInitialized && c.value.size.width > 0 && c.value.size.height > 0) {
      return c.value.size.width > c.value.size.height * 1.05;
    }
    return reel.isLandscape;
  }

  Future<void> _openLandscapeFullscreen(ReelModel reel, VideoPlayerController? controller) async {
    if (controller == null || !controller.value.isInitialized || _isOpeningLandscape) return;
    _isOpeningLandscape = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _LandscapeVideoPlayerPage(
          reel: reel,
          controller: controller,
        ),
      ),
    );
    _isOpeningLandscape = false;
    if (mounted) {
      _syncAllowedOrientationsForIndex(_currentIndex);
      if (widget.isActive && controller.value.isInitialized && !controller.value.isPlaying) {
        controller.play();
      }
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _controllers[_currentIndex]?.pause();
    }
  }

  void _disposeAllControllers() {
    _progressListeners.forEach((idx, listener) {
      _controllers[idx]?.removeListener(listener);
    });
    _progressListeners.clear();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  Future<void> _startVerifiedViewTracking(int index, VideoPlayerController controller) async {
    if (!widget.isActive || index < 0 || index >= _reels.length) return;
    final reel = _reels[index];
    if (_verifiedViewsSent.contains(reel.id)) return;

    // 1. Obtener token firmado con timestamp real del servidor
    if (!_viewTokens.containsKey(reel.id)) {
      final token = await ReelsService.startViewSession(reel.id);
      if (!mounted) return;
      if (token != null && token.isNotEmpty) {
        _viewTokens[reel.id] = token;
      }
    }

    // 2. Acumular tiempo real reproducido (anti-scrubbing: ignora saltos manuales de barra)
    if (_progressListeners.containsKey(index)) {
      controller.removeListener(_progressListeners[index]!);
    }

    _lastObservedPosMs[reel.id] = controller.value.position.inMilliseconds;

    void listener() {
      if (_verifiedViewsSent.contains(reel.id)) return;
      if (!widget.isActive || index != _currentIndex) return;
      if (!controller.value.isInitialized || !controller.value.isPlaying) {
        _lastObservedPosMs[reel.id] = controller.value.position.inMilliseconds;
        return;
      }
      final totalMs = controller.value.duration.inMilliseconds;
      if (totalMs <= 0) return;

      final posMs = controller.value.position.inMilliseconds;
      final prevMs = _lastObservedPosMs[reel.id] ?? posMs;
      _lastObservedPosMs[reel.id] = posMs;

      final deltaMs = posMs - prevMs;
      // Solo acumular avances naturales de reproducción (<= 1.5s entre ticks; ignora adelantos manuales)
      if (deltaMs > 0 && deltaMs <= 1500) {
        final accumulated = (_watchedAccumulatedMs[reel.id] ?? 0) + deltaMs;
        _watchedAccumulatedMs[reel.id] = accumulated;

        final realPercent = ((accumulated / totalMs) * 100).round();
        if (realPercent >= 90) {
          _verifiedViewsSent.add(reel.id);
          final watchedSec = (accumulated / 1000).round();
          ReelsService.recordView(
            reel.id,
            viewToken: _viewTokens[reel.id],
            watchedSeconds: watchedSec,
            watchedPercent: realPercent.clamp(90, 100),
          );
        }
      }
    }

    _progressListeners[index] = listener;
    controller.addListener(listener);
  }

  Future<void> _fetchReels() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _nextCursor = null;
    });
    _disposeAllControllers();

    try {
      final page = await ReelsService.getFeedPage();

      if (mounted) {
        setState(() {
          _reels
            ..clear()
            ..addAll(page.reels);
          _nextCursor = page.nextCursor;
          _isLoading = false;
          _hasError = false;
          _currentIndex = 0;
        });

        if (_reels.isNotEmpty) {
          _initControllerAtIndex(0);
          if (_reels.length > 1) {
            _initControllerAtIndex(1);
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reels.clear();
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _loadMoreReels() async {
    if (_isLoadingMore || _nextCursor == null || _nextCursor!.isEmpty) return;
    _isLoadingMore = true;

    try {
      final page = await ReelsService.getFeedPage(cursor: _nextCursor);
      if (!mounted) return;

      final existingIds = _reels.map((r) => r.id).toSet();
      final fresh = page.reels.where((r) => !existingIds.contains(r.id)).toList();

      setState(() {
        _reels.addAll(fresh);
        _nextCursor = fresh.isNotEmpty ? page.nextCursor : null;
      });
    } catch (_) {
      // Silencioso en paginación secundaria para no interrumpir la reproducción actual
    } finally {
      _isLoadingMore = false;
    }
  }

  void _initControllerAtIndex(int index) {
    if (index < 0 || index >= _reels.length) return;
    if (_controllers.containsKey(index)) return;

    final reel = _reels[index];
    if (reel.videoUrl.isEmpty) return;

    final controller = VideoPlayerController.networkUrl(Uri.parse(reel.videoUrl));

    _controllers[index] = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      controller.setLooping(true);
      controller.setVolume(1.0);
      if (index == _currentIndex && widget.isActive) {
        controller.play();
        _startVerifiedViewTracking(index, controller);
        _syncAllowedOrientationsForIndex(index);
      }
      setState(() {});
    }).catchError((err) {
      debugPrint('Error inicializando video Breif: $err');
    });
  }

  void _onPageChanged(int index) {
    // 1. Pausar video anterior
    _controllers[_currentIndex]?.pause();

    setState(() {
      _currentIndex = index;
    });

    // 2. Reproducir el actual
    final currentCtrl = _controllers[index];
    if (currentCtrl != null && currentCtrl.value.isInitialized) {
      currentCtrl.seekTo(Duration.zero);
      if (widget.isActive) {
        currentCtrl.play();
        _startVerifiedViewTracking(index, currentCtrl);
      }
    } else {
      _initControllerAtIndex(index);
    }
    _syncAllowedOrientationsForIndex(index);

    // 3. Pre-cargar el siguiente video
    if (index + 1 < _reels.length) {
      _initControllerAtIndex(index + 1);
    }

    // 4. Cargar más Breifs automáticamente al acercarse al final del feed
    if (index >= _reels.length - 2) {
      _loadMoreReels();
    }

    // 5. Liberar memoria de videos que estén a más de 1 posición de distancia
    final keysToRemove = <int>[];
    _controllers.forEach((idx, ctrl) {
      if ((idx - index).abs() > 1) {
        final listener = _progressListeners.remove(idx);
        if (listener != null) {
          ctrl.removeListener(listener);
        }
        ctrl.dispose();
        keysToRemove.add(idx);
      }
    });
    for (final k in keysToRemove) {
      _controllers.remove(k);
    }
  }

  Future<void> _handleLike(ReelModel reel) async {
    HapticFeedback.lightImpact();
    setState(() {
      reel.hasLiked = !reel.hasLiked;
      reel.currentLikes = (reel.currentLikes + (reel.hasLiked ? 1 : -1)).clamp(0, 999999999);
    });

    try {
      final res = await ReelsService.toggleLike(reel.id);
      if (mounted && res['likes_count'] != null) {
        setState(() {
          reel.currentLikes = (res['likes_count'] as num).toInt();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          reel.hasLiked = !reel.hasLiked;
          reel.currentLikes = (reel.currentLikes + (reel.hasLiked ? 1 : -1)).clamp(0, 999999999);
        });
      }
    }
  }

  Future<void> _handleSave(ReelModel reel) async {
    HapticFeedback.selectionClick();
    setState(() {
      reel.hasSaved = !reel.hasSaved;
      reel.currentSaves = (reel.currentSaves + (reel.hasSaved ? 1 : -1)).clamp(0, 999999999);
    });

    try {
      final res = await ReelsService.toggleSave(reel.id);
      if (mounted) {
        if (res['saves_count'] != null) {
          setState(() {
            reel.currentSaves = (res['saves_count'] as num).toInt();
          });
        }
        AppSnackBar.showInfo(
          context,
          reel.hasSaved ? tr('breif_saved_added') : tr('breif_saved_removed'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          reel.hasSaved = !reel.hasSaved;
          reel.currentSaves = (reel.currentSaves + (reel.hasSaved ? 1 : -1)).clamp(0, 999999999);
        });
      }
    }
  }

  void _openComments(ReelModel reel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentsBottomSheet(
        reel: reel,
        onCommentAdded: () {
          if (mounted) {
            setState(() {
              reel.currentComments += 1;
            });
          }
        },
      ),
    );
  }

  void _handleReport(ReelModel reel) {
    final reasons = <Map<String, String>>[
      {'key': 'nsfw_gore', 'label': tr('breif_report_nsfw_gore')},
      {'key': 'harassment_hate', 'label': tr('breif_report_harassment_hate')},
      {'key': 'impersonation_stolen', 'label': tr('breif_report_impersonation_stolen')},
      {'key': 'spam', 'label': tr('breif_report_spam')},
      {'key': 'off_topic', 'label': tr('breif_report_off_topic')},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('breif_report_title'),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr('breif_report_subtitle'),
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                ...reasons.map((item) {
                  final isSevere = item['key'] == 'nsfw_gore';
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    leading: Icon(
                      isSevere ? Icons.warning_amber_rounded : Icons.flag_outlined,
                      color: AppTheme.hextechCrimson,
                      size: 20,
                    ),
                    title: Text(
                      item['label']!,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: isSevere ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      try {
                        final msg = await ReelsService.reportReel(reel.id, reason: item['key']!);
                        if (mounted) {
                          AppSnackBar.showSuccess(context, msg);
                          if (isSevere) {
                            setState(() {
                              _reels.removeWhere((r) => r.id == reel.id);
                            });
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          AppSnackBar.showError(
                            context,
                            e is ApiException ? e.message : tr('breif_report_error'),
                          );
                        }
                      }
                    },
                  );
                }),
                const Divider(color: Colors.white12, height: 18),
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: const Icon(Icons.block_rounded, color: Colors.orangeAccent, size: 20),
                  title: Text(
                    tr('breif_block_creator', {'user': reel.creatorUsername}),
                    style: GoogleFonts.inter(
                      color: Colors.orangeAccent,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    tr('breif_block_creator_desc'),
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    try {
                      final res = await ReelsService.toggleBlockUser(reel.creatorId);
                      if (mounted) {
                        final isBlocked = res['blocked'] == true;
                        final msg = res['message']?.toString() ?? tr('breif_block_creator', {'user': reel.creatorUsername});
                        AppSnackBar.showSuccess(context, msg);
                        if (isBlocked) {
                          setState(() {
                            _reels.removeWhere((r) => r.creatorId == reel.creatorId);
                          });
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        AppSnackBar.showError(
                          context,
                          e is ApiException ? e.message : tr('breif_block_error'),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleFollow(ReelModel reel) async {
    HapticFeedback.lightImpact();
    final prevFollowing = reel.isFollowing;
    final nextFollowing = !prevFollowing;
    setState(() {
      for (final item in _reels) {
        if (item.creatorId == reel.creatorId) {
          item.isFollowing = nextFollowing;
          item.currentFollowers = (item.currentFollowers + (nextFollowing ? 1 : -1)).clamp(0, 999999999);
        }
      }
    });

    try {
      final res = await ReelsService.toggleFollow(reel.creatorId);
      final serverFollowing = res['following'] == true;
      final serverFollowers = (res['followers_count'] as num?)?.toInt();
      if (mounted) {
        setState(() {
          for (final item in _reels) {
            if (item.creatorId == reel.creatorId) {
              item.isFollowing = serverFollowing;
              if (serverFollowers != null) {
                item.currentFollowers = serverFollowers;
              }
            }
          }
        });
        AppSnackBar.showInfo(
          context,
          serverFollowing
              ? tr('breif_following_snack', {'user': reel.creatorUsername})
              : tr('breif_unfollow_snack', {'user': reel.creatorUsername}),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          for (final item in _reels) {
            if (item.creatorId == reel.creatorId) {
              item.isFollowing = prevFollowing;
              item.currentFollowers = (item.currentFollowers + (prevFollowing ? 1 : -1)).clamp(0, 999999999);
            }
          }
        });
        AppSnackBar.showError(
          context,
          e is ApiException ? e.message : 'No se pudo actualizar el seguimiento',
        );
      }
    }
  }

  void _openCreatorProfile(ReelModel reel) {
    final fallbackReels = _reels.where((r) => r.creatorId == reel.creatorId).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CreatorProfileBottomSheet(
        reel: reel,
        initialReels: fallbackReels,
        onToggleFollow: () => _handleFollow(reel),
      ),
    );
  }

  void _openUploadReel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UploadReelBottomSheet(
        onSuccess: () => _fetchReels(),
      ),
    );
  }

  void _openProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ReelsProfileBottomSheet(
        userPhotoUrl: widget.userPhotoUrl,
        onReelDeleted: () => _fetchReels(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Feed de Video
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.hextechCyan),
            )
          else if (_hasError)
            _buildErrorState()
          else if (_reels.isEmpty)
            _buildEmptyState()
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: _reels.length,
              itemBuilder: (context, index) {
                final reel = _reels[index];
                final controller = _controllers[index];
                return _ReelPlayerItem(
                  reel: reel,
                  controller: controller,
                  onDoubleTap: () => _handleLike(reel),
                  onLike: () => _handleLike(reel),
                  onSave: () => _handleSave(reel),
                  onComments: () => _openComments(reel),
                  onReport: () => _handleReport(reel),
                  onFollow: () => _handleFollow(reel),
                  onOpenCreatorProfile: () => _openCreatorProfile(reel),
                  onRotateFullscreen: () => _openLandscapeFullscreen(reel, controller),
                );
              },
            ),

          // Top Bar Superpuesta
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [AppTheme.hextechCrimson, AppTheme.hextechPink],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.hextechCrimson.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.movie_filter_rounded, color: Colors.white, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tr('breif_title'),
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Botón Subir Breif
                          IconButton(
                            onPressed: _openUploadReel,
                            tooltip: tr('breif_upload_tooltip'),
                            icon: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.hextechCyan.withValues(alpha: 0.2),
                                border: Border.all(color: AppTheme.hextechCyan, width: 1.5),
                              ),
                              child: const Icon(Icons.add_rounded, color: AppTheme.hextechCyan, size: 20),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Botón Mi Perfil con foto del usuario
                          GestureDetector(
                            onTap: _openProfile,
                            child: _buildUserAvatar(widget.userPhotoUrl, size: 34),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(String? photoUrl, {double size = 34}) {
    final hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.hextechCyan.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildAvatarFallback(size),
              )
            : _buildAvatarFallback(size),
      ),
    );
  }

  Widget _buildAvatarFallback(double size) {
    return Container(
      color: AppTheme.cardDark,
      alignment: Alignment.center,
      child: Icon(
        Icons.person_outline_rounded,
        color: Colors.white,
        size: size * 0.58,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_collection_outlined, size: 64, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              tr('breif_empty_title'),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _openUploadReel,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.hextechCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                tr('breif_empty_btn'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 58, color: Colors.white.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(
              tr('breif_error_title'),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _fetchReels,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.hextechCyan,
                side: const BorderSide(color: AppTheme.hextechCyan),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr('breif_retry'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatCompactCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
  }
  return '$value';
}

// Item Individual del Reproductor
class _ReelPlayerItem extends StatefulWidget {
  final ReelModel reel;
  final VideoPlayerController? controller;
  final VoidCallback onDoubleTap;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onComments;
  final VoidCallback onReport;
  final VoidCallback onFollow;
  final VoidCallback onOpenCreatorProfile;
  final VoidCallback onRotateFullscreen;

  const _ReelPlayerItem({
    required this.reel,
    required this.controller,
    required this.onDoubleTap,
    required this.onLike,
    required this.onSave,
    required this.onComments,
    required this.onReport,
    required this.onFollow,
    required this.onOpenCreatorProfile,
    required this.onRotateFullscreen,
  });

  @override
  State<_ReelPlayerItem> createState() => _ReelPlayerItemState();
}

class _ReelPlayerItemState extends State<_ReelPlayerItem> {
  bool _showHeartAnimation = false;
  bool _isPausedManually = false;
  bool _isActionsExpanded = false;

  void _triggerDoubleTap() {
    widget.onDoubleTap();
    setState(() => _showHeartAnimation = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showHeartAnimation = false);
    });
  }

  void _togglePlayPause() {
    if (_isActionsExpanded) {
      setState(() => _isActionsExpanded = false);
      return;
    }
    if (widget.controller == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (widget.controller!.value.isPlaying) {
        widget.controller!.pause();
        _isPausedManually = true;
      } else {
        widget.controller!.play();
        _isPausedManually = false;
      }
    });
  }

  void _toggleActionsMenu() {
    HapticFeedback.selectionClick();
    setState(() => _isActionsExpanded = !_isActionsExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final isInitialized = c != null && c.value.isInitialized;
    final lang = LanguageService.instance;
    final isLandscapeVideo = isInitialized && c.value.size.width > 0 && c.value.size.height > 0
        ? (c.value.size.width > c.value.size.height * 1.05)
        : widget.reel.isLandscape;
    final videoAspect = isInitialized && c.value.aspectRatio > 0
        ? c.value.aspectRatio
        : (isLandscapeVideo ? 16 / 9 : 9 / 16);
    final isDeviceLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return GestureDetector(
      onTap: _togglePlayPause,
      onDoubleTap: _triggerDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video Player adaptado automáticamente a vertical (cover) u horizontal (contain sin recorte)
          if (isInitialized)
            isLandscapeVideo
                ? Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: AspectRatio(
                      aspectRatio: videoAspect,
                      child: VideoPlayer(c),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
                    ),
                  )
          else
            Stack(
              fit: StackFit.expand,
              children: [
                if (widget.reel.thumbnailUrl.isNotEmpty)
                  Image.network(
                    widget.reel.thumbnailUrl,
                    fit: isLandscapeVideo ? BoxFit.contain : BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(color: Colors.black),
                  )
                else
                  Container(color: Colors.black),
                const Center(
                  child: CircularProgressIndicator(color: AppTheme.hextechCyan, strokeWidth: 2),
                ),
              ],
            ),

          // Botón de rotación a pantalla completa cuando el video es horizontal y el teléfono está vertical
          if (isInitialized && isLandscapeVideo && !isDeviceLandscape)
            Positioned(
              right: 16,
              bottom: 136,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onRotateFullscreen();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xD90B1220),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.hextechCyan.withValues(alpha: 0.75),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.screen_rotation_rounded, color: AppTheme.hextechCyan, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Horizontal',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Gradiente superior sutil para legibilidad de la barra superior
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 110,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Gradiente inferior para legibilidad
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 240,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.88),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Ícono de Pausa cuando se pausa manualmente
          if (_isPausedManually)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 54),
              ),
            ),

          // Animación de Corazón en Doble Tap
          if (_showHeartAnimation)
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.5, end: 1.3),
                duration: const Duration(milliseconds: 300),
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: AppTheme.hextechCrimson,
                      size: 90,
                    ),
                  );
                },
              ),
            ),

          // Perfil del Creador en esquina inferior derecha con menú desplegable hacia arriba
          Positioned(
            right: 16,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Menú desplegable hacia arriba (Corazón, Mensaje, Guardar, Reportar)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                    );
                  },
                  child: _isActionsExpanded
                      ? Container(
                          key: const ValueKey('breif_actions_open'),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xD90B1220),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: AppTheme.hextechCyan.withValues(alpha: 0.35),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildActionButton(
                                icon: widget.reel.hasLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: widget.reel.hasLiked ? AppTheme.hextechCrimson : Colors.white,
                                label: _formatCompactCount(widget.reel.currentLikes),
                                onTap: widget.onLike,
                              ),
                              const SizedBox(height: 12),
                              _buildActionButton(
                                icon: Icons.chat_bubble_outline_rounded,
                                color: Colors.white,
                                label: _formatCompactCount(widget.reel.currentComments),
                                onTap: () {
                                  setState(() => _isActionsExpanded = false);
                                  widget.onComments();
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildActionButton(
                                icon: widget.reel.hasSaved
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                                color: widget.reel.hasSaved ? AppTheme.hextechGold : Colors.white,
                                label: _formatCompactCount(widget.reel.currentSaves),
                                onTap: widget.onSave,
                              ),
                              const SizedBox(height: 12),
                              _buildActionButton(
                                icon: Icons.flag_outlined,
                                color: Colors.white70,
                                label: lang.tr('breif_report'),
                                onTap: () {
                                  setState(() => _isActionsExpanded = false);
                                  widget.onReport();
                                },
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('breif_actions_closed')),
                ),

                // Avatar del creador (Botón desplegable)
                GestureDetector(
                  onTap: _toggleActionsMenu,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isActionsExpanded
                                ? AppTheme.hextechCyan
                                : AppTheme.hextechCyan.withValues(alpha: 0.75),
                            width: _isActionsExpanded ? 2.4 : 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.hextechCyan.withValues(
                                alpha: _isActionsExpanded ? 0.5 : 0.25,
                              ),
                              blurRadius: _isActionsExpanded ? 14 : 8,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: widget.reel.creatorAvatar.isNotEmpty
                                ? Image.network(
                                    widget.reel.creatorAvatar,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: AppTheme.cardDark,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.person_rounded, color: Colors.white70, size: 22),
                                    ),
                                  )
                                : Container(
                                    color: AppTheme.cardDark,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.person_rounded, color: Colors.white70, size: 22),
                                  ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _isActionsExpanded ? AppTheme.hextechCyan : const Color(0xE60B1220),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.hextechCyan.withValues(alpha: 0.8),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            _isActionsExpanded
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_up_rounded,
                            size: 13,
                            color: _isActionsExpanded ? Colors.black : AppTheme.hextechCyan,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Información del Breif en la parte inferior izquierda (alineada con el perfil)
          Positioned(
            left: 16,
            right: 84,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nombre de usuario (tappable para ir a su perfil) + botón (+) para seguir
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: widget.onOpenCreatorProfile,
                        child: Text(
                          '@${widget.reel.creatorUsername}',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onFollow,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.reel.isFollowing
                              ? Colors.white.withValues(alpha: 0.16)
                              : AppTheme.hextechCyan.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.reel.isFollowing
                                ? Colors.white54
                                : AppTheme.hextechCyan,
                            width: 1.1,
                          ),
                        ),
                        child: Icon(
                          widget.reel.isFollowing ? Icons.check_rounded : Icons.add_rounded,
                          size: 14,
                          color: widget.reel.isFollowing ? Colors.white : AppTheme.hextechCyan,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Título
                Text(
                  widget.reel.title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Estadísticas: Likes y Seguidores
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.reel.hasLiked
                              ? AppTheme.hextechCrimson.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.reel.hasLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 12,
                            color: widget.reel.hasLiked
                                ? AppTheme.hextechCrimson
                                : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            lang.tr('breif_likes_label', {
                              'count': _formatCompactCount(widget.reel.currentLikes),
                            }),
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.people_outline_rounded,
                            size: 12,
                            color: AppTheme.hextechCyan,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            lang.tr('breif_followers_label', {
                              'count': _formatCompactCount(widget.reel.currentFollowers),
                            }),
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Barra de progreso inferior
          if (isInitialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: AppTheme.hextechCyan,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Modal de Comentarios
class _CommentsBottomSheet extends StatefulWidget {
  final ReelModel reel;
  final VoidCallback? onCommentAdded;

  const _CommentsBottomSheet({
    required this.reel,
    this.onCommentAdded,
  });

  @override
  State<_CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<_CommentsBottomSheet> {
  final List<ReelCommentModel> _comments = [];
  final TextEditingController _textCtrl = TextEditingController();
  bool _isLoading = true;
  bool _isPosting = false;

  String _tr(String key, [Map<String, String>? params]) => LanguageService.instance.tr(key, params);

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final list = await ReelsService.getComments(widget.reel.id);
      if (mounted) {
        setState(() {
          _comments
            ..clear()
            ..addAll(list);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitComment() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPosting = true);
    _textCtrl.clear();
    FocusScope.of(context).unfocus();

    try {
      final newComment = await ReelsService.addComment(widget.reel.id, text);
      if (mounted) {
        setState(() {
          _comments.insert(0, newComment);
          _isPosting = false;
        });
        widget.onCommentAdded?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPosting = false);
        AppSnackBar.showError(
          context,
          e is ApiException ? e.message : _tr('breif_comments_error'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _tr('breif_comments_title', {'count': '${_comments.length}'}),
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),

            // Lista de comentarios
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.hextechCyan))
                  : _comments.isEmpty
                      ? Center(
                          child: Text(
                            _tr('breif_comments_empty'),
                            style: GoogleFonts.outfit(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _comments.length,
                          itemBuilder: (context, index) {
                            final item = _comments[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipOval(
                                    child: SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: item.profilePic.isNotEmpty
                                          ? Image.network(
                                              item.profilePic,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) => Container(
                                                color: Colors.white12,
                                                alignment: Alignment.center,
                                                child: const Icon(Icons.person, size: 18, color: Colors.white70),
                                              ),
                                            )
                                          : Container(
                                              color: Colors.white12,
                                              alignment: Alignment.center,
                                              child: const Icon(Icons.person, size: 18, color: Colors.white70),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '@${item.username}',
                                          style: GoogleFonts.outfit(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item.content,
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Input de Comentario
            SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _isPosting ? null : _submitComment(),
                        decoration: InputDecoration(
                          hintText: _tr('breif_comments_hint'),
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isPosting ? null : _submitComment,
                      icon: _isPosting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: AppTheme.hextechCyan, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, color: AppTheme.hextechCyan),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Modal de Subida de Breif
class _UploadReelBottomSheet extends StatefulWidget {
  final VoidCallback onSuccess;

  const _UploadReelBottomSheet({required this.onSuccess});

  @override
  State<_UploadReelBottomSheet> createState() => _UploadReelBottomSheetState();
}

class _UploadReelBottomSheetState extends State<_UploadReelBottomSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _tagCtrl = TextEditingController();

  File? _videoFile;
  int _videoDurationSeconds = 0;
  int _videoWidth = 0;
  int _videoHeight = 0;
  bool _isUploading = false;
  String _uploadStageText = '';

  static const int _minDurationSec = 10;
  static const int _maxDurationSec = 30;
  static const int _maxCompressedBytes = 15 * 1024 * 1024; // 15 MB máx. en 720p
  static const int _maxTags = 6;

  final List<String> _selectedTags = [];
  static const List<String> _suggestedTags = [
    'pentakill',
    'outplay',
    'combo',
    'baron',
    'ranked',
    'meme',
    'wildrift',
    'lolpc',
  ];

  String _tr(String key, [Map<String, String>? params]) => LanguageService.instance.tr(key, params);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  /// Detecta automáticamente el idioma del contenido según la región/país del dispositivo.
  String _detectLanguageByRegion() {
    final locale = PlatformDispatcher.instance.locale;
    final country = (locale.countryCode ?? '').toUpperCase();
    final lang = locale.languageCode.toLowerCase();

    const spanishCountries = {
      'ES', 'MX', 'CO', 'AR', 'CL', 'PE', 'EC', 'VE', 'UY', 'PY',
      'BO', 'CR', 'PA', 'DO', 'GT', 'HN', 'SV', 'NI', 'PR', 'CU',
    };
    const portugueseCountries = {'BR', 'PT', 'AO', 'MZ'};
    const englishCountries = {'US', 'GB', 'AU', 'NZ', 'IE'};
    const frenchCountries = {'FR', 'MC'};

    if (portugueseCountries.contains(country)) return 'pt';
    if (frenchCountries.contains(country)) return 'fr';
    if (spanishCountries.contains(country)) return 'es';
    if (englishCountries.contains(country)) return 'en';
    if (country == 'CA' || country == 'BE' || country == 'CH') {
      return lang == 'fr' ? 'fr' : 'en';
    }
    return LanguageService.normalizeCode(
      lang.isNotEmpty ? lang : LanguageService.instance.currentLanguage,
    );
  }

  void _addTag(String raw) {
    final cleaned = raw
        .trim()
        .toLowerCase()
        .replaceAll('#', '')
        .replaceAll(RegExp(r'[^a-z0-9áéíóúñç_]'), '');
    if (cleaned.isEmpty) return;
    if (_selectedTags.contains(cleaned)) {
      _tagCtrl.clear();
      return;
    }
    if (_selectedTags.length >= _maxTags) {
      AppSnackBar.showInfo(context, _tr('breif_tags_max', {'max': '$_maxTags'}));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _selectedTags.add(cleaned);
      _tagCtrl.clear();
    });
  }

  void _toggleSuggestedTag(String tag) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else if (_selectedTags.length < _maxTags) {
        _selectedTags.add(tag);
      } else {
        AppSnackBar.showInfo(context, _tr('breif_tags_max', {'max': '$_maxTags'}));
      }
    });
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: _maxDurationSec),
    );
    if (picked == null) return;

    try {
      final info = await VideoCompress.getMediaInfo(picked.path);
      final durationSec = ((info.duration ?? 0) / 1000).round();

      if (durationSec < _minDurationSec || durationSec > _maxDurationSec) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            _tr('breif_upload_duration_err', {
              'min': '$_minDurationSec',
              'max': '$_maxDurationSec',
              'sec': '$durationSec',
            }),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _videoFile = File(picked.path);
          _videoDurationSeconds = durationSec;
          _videoWidth = info.width ?? 0;
          _videoHeight = info.height ?? 0;
        });
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.showError(context, _tr('breif_upload_read_err'));
      }
    }
  }

  Future<void> _publishReel() async {
    final title = _titleCtrl.text.trim();
    if (title.length < 3) {
      AppSnackBar.showError(context, _tr('breif_upload_title_err'));
      return;
    }
    if (_videoFile == null) {
      AppSnackBar.showError(context, _tr('breif_upload_video_err'));
      return;
    }
    if (_videoDurationSeconds < _minDurationSec || _videoDurationSeconds > _maxDurationSec) {
      AppSnackBar.showError(
        context,
        _tr('breif_upload_range_err', {'min': '$_minDurationSec', 'max': '$_maxDurationSec'}),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStageText = _tr('breif_upload_stage_compress');
    });

    File? compressedFile;
    File? thumbFile;

    try {
      // 1. Compresión obligatoria en el dispositivo a 720p H.264
      final compressedInfo = await VideoCompress.compressVideo(
        _videoFile!.path,
        quality: VideoQuality.Res1280x720Quality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30,
      );

      compressedFile = compressedInfo?.file ?? _videoFile!;
      final compressedBytes = await compressedFile.length();
      if (compressedBytes > _maxCompressedBytes) {
        throw ApiException(_tr('breif_upload_size_err'));
      }

      // 2. Generar thumbnail ligero automáticamente
      try {
        thumbFile = await VideoCompress.getFileThumbnail(
          compressedFile.path,
          quality: 70,
          position: 1,
        );
      } catch (_) {}

      if (mounted) {
        setState(() => _uploadStageText = _tr('breif_upload_stage_upload'));
      }

      // 3. Subida directa prefirmada a Cloudflare R2 / S3 (con fallback local)
      final uploadRes = await ReelsService.uploadMedia(
        videoFile: compressedFile,
        thumbnailFile: thumbFile,
        durationSeconds: _videoDurationSeconds,
      );
      final videoUrl = uploadRes['video_url']?.toString() ?? '';
      final videoKey = uploadRes['video_key']?.toString() ?? '';
      final thumbnailUrl = uploadRes['thumbnail_url']?.toString() ?? '';
      final fileSizeBytes = (uploadRes['file_size_bytes'] as num?)?.toInt() ?? compressedBytes;

      if (mounted) {
        setState(() => _uploadStageText = _tr('breif_upload_stage_publish'));
      }

      // 4. Registrar Breif en el backend (idioma detectado por región, orientación y etiquetas SEO)
      final detectedLang = _detectLanguageByRegion();
      final tagsText = _selectedTags.map((t) => '#$t').join(' ');
      final finalWidth = compressedInfo?.width ?? _videoWidth;
      final finalHeight = compressedInfo?.height ?? _videoHeight;
      final detectedOrientation =
          (finalWidth > 0 && finalHeight > 0 && finalWidth > finalHeight * 1.05)
              ? 'landscape'
              : 'portrait';
      await ReelsService.createReel({
        'title': title,
        'description': tagsText,
        'tags': _selectedTags,
        'video_url': videoUrl,
        'video_key': videoKey,
        'thumbnail_url': thumbnailUrl,
        'game_mode': 'wild_rift',
        'category': 'jugadas',
        'language': detectedLang,
        'champion_name': _selectedTags.isNotEmpty ? _selectedTags.first : '',
        'duration_seconds': _videoDurationSeconds,
        'file_size_bytes': fileSizeBytes,
        'width': finalWidth,
        'height': finalHeight,
        'orientation': detectedOrientation,
      });

      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.showSuccess(context, _tr('breif_upload_success'));
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        AppSnackBar.showError(
          context,
          e is ApiException ? e.message : _tr('breif_upload_error'),
        );
      }
    } finally {
      try {
        await VideoCompress.deleteAllCache();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _tr('breif_upload_title'),
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ListView(
                children: [
                  // Selector de video
                  InkWell(
                    onTap: _pickVideo,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 140,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _videoFile != null ? AppTheme.hextechCyan : Colors.white24,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: _videoFile == null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.video_library_rounded, color: AppTheme.hextechCyan, size: 36),
                                  const SizedBox(height: 8),
                                  Text(
                                    _tr('breif_upload_pick_hint'),
                                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12.5),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: AppTheme.hextechCyan, size: 36),
                                  const SizedBox(height: 8),
                                  Text(
                                    _tr('breif_upload_ready', {'sec': '$_videoDurationSeconds'}),
                                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Título
                  TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _tr('breif_upload_title_label'),
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sistema de Etiquetas (SEO y recomendaciones)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _tr('breif_tags_title'),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_selectedTags.length}/$_maxTags',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tr('breif_tags_subtitle'),
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tagCtrl,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.done,
                    onSubmitted: _addTag,
                    onChanged: (val) {
                      if (val.endsWith(' ') || val.endsWith(',')) {
                        _addTag(val);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: _tr('breif_tags_hint'),
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      prefixText: '# ',
                      prefixStyle: const TextStyle(
                        color: AppTheme.hextechCyan,
                        fontWeight: FontWeight.bold,
                      ),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => _addTag(_tagCtrl.text),
                        icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.hextechCyan),
                      ),
                    ),
                  ),
                  if (_selectedTags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _selectedTags.map((tag) {
                        return Chip(
                          label: Text(
                            '#$tag',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: AppTheme.hextechCyan.withValues(alpha: 0.2),
                          side: BorderSide(color: AppTheme.hextechCyan.withValues(alpha: 0.7)),
                          deleteIcon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                          onDeleted: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedTags.remove(tag));
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _tr('breif_tags_suggested'),
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _suggestedTags.map((tag) {
                      final isSelected = _selectedTags.contains(tag);
                      return InkWell(
                        onTap: () => _toggleSuggestedTag(tag),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.hextechCyan.withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? AppTheme.hextechCyan : Colors.white24,
                            ),
                          ),
                          child: Text(
                            '#$tag',
                            style: GoogleFonts.inter(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Botón Publicar
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _publishReel,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.hextechCyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isUploading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(_uploadStageText, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      )
                    : Text(
                        _tr('breif_upload_btn'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Modal Perfil de Breifs del Usuario Actual
class _ReelsProfileBottomSheet extends StatefulWidget {
  final String? userPhotoUrl;
  final VoidCallback? onReelDeleted;

  const _ReelsProfileBottomSheet({
    this.userPhotoUrl,
    this.onReelDeleted,
  });

  @override
  State<_ReelsProfileBottomSheet> createState() => _ReelsProfileBottomSheetState();
}

class _ReelsProfileBottomSheetState extends State<_ReelsProfileBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  CreatorSocialProfile? _mySocial;
  UserReelsStats? _stats;
  List<ReelModel> _myReels = [];
  List<ReelModel> _likedReels = [];
  List<ReelModel> _savedReels = [];
  bool _isLoading = true;

  String _tr(String key, [Map<String, String>? params]) => LanguageService.instance.tr(key, params);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadProfileData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    try {
      final results = await Future.wait([
        ReelsService.getMyUploadedReels(),
        ReelsService.getMyLikedReels(),
        ReelsService.getMySavedReels(),
      ]);
      final myData = results[0] as Map<String, dynamic>;
      final liked = results[1] as List<ReelModel>;
      final saved = results[2] as List<ReelModel>;

      if (mounted) {
        setState(() {
          _mySocial = myData['user'] as CreatorSocialProfile?;
          _stats = myData['stats'] as UserReelsStats?;
          _myReels = (myData['reels'] as List<ReelModel>?) ?? [];
          _likedReels = liked;
          _savedReels = saved;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openEditProfile() async {
    final updated = await showModalBottomSheet<CreatorSocialProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditCreatorProfileDialog(initial: _mySocial ?? const CreatorSocialProfile()),
    );
    if (updated != null && mounted) {
      setState(() => _mySocial = updated);
    }
  }

  Future<void> _openPayoutDialog() async {
    final stats = _stats;
    if (stats == null) return;
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayoutRequestDialog(stats: stats),
    );
    if (submitted == true && mounted) {
      _loadProfileData();
    }
  }

  void _playGridReel(ReelModel reel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (_) => _SingleReelPlayerSheet(reel: reel),
    );
  }

  Future<void> _confirmDeleteReel(ReelModel reel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _tr('breif_delete_title'),
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          _tr('breif_delete_body'),
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(_tr('cancel'), style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.hextechCrimson,
              foregroundColor: Colors.white,
            ),
            child: Text(_tr('breif_delete_confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ReelsService.deleteReel(reel.id);
      if (mounted) {
        setState(() {
          _myReels.removeWhere((r) => r.id == reel.id);
        });
        AppSnackBar.showSuccess(context, _tr('breif_delete_success'));
        widget.onReelDeleted?.call();
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          e is ApiException ? e.message : _tr('breif_delete_error'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final social = _mySocial;
    final stats = _stats;
    final availableUsd = stats?.availableBalanceUsd ?? 0.0;
    final minPayoutUsd = stats?.minPayoutUsd ?? 100.0;
    final progress = (availableUsd / (minPayoutUsd > 0 ? minPayoutUsd : 100.0)).clamp(0.0, 1.0);

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: const BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.hextechCyan))
          : Column(
              children: [
                // Header Handle + Botón Editar Perfil
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 72),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openEditProfile,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.hextechCyan,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.edit_rounded, size: 15),
                        label: Text(
                          'Editar',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),

                // Avatar + @username
                Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.hextechCyan, width: 2),
                  ),
                  child: ClipOval(
                    child: (widget.userPhotoUrl != null && widget.userPhotoUrl!.trim().isNotEmpty)
                        ? Image.network(
                            widget.userPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.white12,
                              alignment: Alignment.center,
                              child: const Icon(Icons.person_rounded, color: Colors.white70, size: 28),
                            ),
                          )
                        : Container(
                            color: Colors.white12,
                            alignment: Alignment.center,
                            child: const Icon(Icons.person_rounded, color: Colors.white70, size: 28),
                          ),
                  ),
                ),
                if (social != null && social.username.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '@${social.username}',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (social != null && social.bio.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      social.bio,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
                if (social != null && social.hasAnySocialLink) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _SocialLinksRow(profile: social),
                  ),
                ],
                const SizedBox(height: 8),

                // Resumen de Métricas (Videos, Vistas Totales, Vistas Verificadas, Likes)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard(
                        _tr('breif_profile_videos'),
                        '${stats?.totalReels ?? _myReels.length}',
                        Icons.movie_outlined,
                      ),
                      _buildStatCard(
                        _tr('breif_profile_views'),
                        _formatCompactCount(stats?.totalViews ?? 0),
                        Icons.visibility_outlined,
                      ),
                      _buildStatCard(
                        'Verificadas',
                        _formatCompactCount(stats?.lifetimeVerifiedViews ?? 0),
                        Icons.verified_outlined,
                      ),
                      _buildStatCard(
                        _tr('breif_profile_likes'),
                        _formatCompactCount(stats?.totalLikes ?? 0),
                        Icons.favorite_border_rounded,
                      ),
                    ],
                  ),
                ),

                // Tarjeta compacta de Monetización ($0.01 / 1,000 vistas verificadas • Mín. $100 USD)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (stats?.canWithdraw == true)
                            ? AppTheme.hextechGold.withValues(alpha: 0.7)
                            : AppTheme.hextechCyan.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Saldo disponible: \$${availableUsd.toStringAsFixed(4)} USD',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '\$0.01 por cada 1,000 vistas verificadas (90% único)',
                                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 10.5),
                                ),
                              ],
                            ),
                            ElevatedButton(
                              onPressed: _openPayoutDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: (stats?.canWithdraw == true)
                                    ? AppTheme.hextechGold
                                    : Colors.white12,
                                foregroundColor: (stats?.canWithdraw == true)
                                    ? Colors.black
                                    : Colors.white70,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                'Retirar',
                                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              (stats?.canWithdraw == true) ? AppTheme.hextechGold : AppTheme.hextechCyan,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Meta mínima de retiro: \$${minPayoutUsd.toStringAsFixed(0)} USD (${(progress * 100).toStringAsFixed(2)}%)',
                          style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),

                // Tabs (Mis Videos, Me Gusta, Guardados)
                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: AppTheme.hextechCyan,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  tabs: [
                    Tab(icon: const Icon(Icons.grid_on_rounded), text: _tr('breif_profile_tab_mine')),
                    Tab(icon: const Icon(Icons.favorite_rounded), text: _tr('breif_profile_tab_liked')),
                    Tab(icon: const Icon(Icons.bookmark_rounded), text: _tr('breif_profile_tab_saved')),
                  ],
                ),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildReelsGrid(
                        _myReels,
                        emptyMsg: _tr('breif_profile_empty_mine'),
                        allowDelete: true,
                      ),
                      _buildReelsGrid(_likedReels, emptyMsg: _tr('breif_profile_empty_liked')),
                      _buildReelsGrid(_savedReels, emptyMsg: _tr('breif_profile_empty_saved')),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.hextechCyan, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildReelsGrid(
    List<ReelModel> list, {
    required String emptyMsg,
    bool allowDelete = false,
  }) {
    if (list.isEmpty) {
      return Center(
        child: Text(emptyMsg, style: GoogleFonts.outfit(color: Colors.white54)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.65,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final reel = list[index];
        return GestureDetector(
          onTap: () => _playGridReel(reel),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.black45,
              border: Border.all(color: Colors.white12),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (reel.thumbnailUrl.isNotEmpty)
                  Image.network(
                    reel.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(
                        Icons.play_circle_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 32,
                      ),
                    ),
                  )
                else
                  Center(
                    child: Icon(
                      Icons.play_circle_outline_rounded,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 32,
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                if (allowDelete)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _confirmDeleteReel(reel),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppTheme.hextechCrimson,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Row(
                    children: [
                      const Icon(Icons.visibility, color: Colors.white70, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        _formatCompactCount(reel.viewsCount),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

// Modal de Perfil Público de un Creador (al presionar @username)
class _CreatorProfileBottomSheet extends StatefulWidget {
  final ReelModel reel;
  final List<ReelModel> initialReels;
  final VoidCallback onToggleFollow;

  const _CreatorProfileBottomSheet({
    required this.reel,
    required this.initialReels,
    required this.onToggleFollow,
  });

  @override
  State<_CreatorProfileBottomSheet> createState() => _CreatorProfileBottomSheetState();
}

class _CreatorProfileBottomSheetState extends State<_CreatorProfileBottomSheet> {
  CreatorReelsProfile? _profile;
  bool _isLoading = true;

  String _tr(String key, [Map<String, String>? params]) => LanguageService.instance.tr(key, params);

  @override
  void initState() {
    super.initState();
    _loadCreatorProfile();
  }

  Future<void> _loadCreatorProfile() async {
    try {
      final profile = await ReelsService.getUserProfile(widget.reel.creatorId);
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final social = _profile?.social;
    final username = (_profile?.username.isNotEmpty == true)
        ? _profile!.username
        : reel.creatorUsername;
    final avatarUrl = (_profile?.profilePic.isNotEmpty == true)
        ? _profile!.profilePic
        : reel.creatorAvatar;
    final reelsList = _profile?.reels ?? widget.initialReels;
    final totalViews = _profile?.stats?.totalViews ??
        reelsList.fold<int>(0, (sum, item) => sum + item.viewsCount);
    final totalLikes = _profile?.stats?.totalLikes ??
        reelsList.fold<int>(0, (sum, item) => sum + item.currentLikes);
    final totalVideos = _profile?.stats?.totalReels ?? reelsList.length;
    final followersCount = _profile?.stats?.followersCount ?? reel.currentFollowers;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Avatar + @username + Bio + Links sociales + Botón Seguir
          Container(
            width: 66,
            height: 66,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.hextechCyan, width: 2),
            ),
            child: ClipOval(
              child: avatarUrl.isNotEmpty
                  ? Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.white12,
                        alignment: Alignment.center,
                        child: const Icon(Icons.person_rounded, color: Colors.white70, size: 34),
                      ),
                    )
                  : Container(
                      color: Colors.white12,
                      alignment: Alignment.center,
                      child: const Icon(Icons.person_rounded, color: Colors.white70, size: 34),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '@$username',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (social != null && social.bio.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                social.bio,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5),
              ),
            ),
          ],
          if (social != null && social.hasAnySocialLink) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SocialLinksRow(profile: social),
            ),
          ],
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () {
              widget.onToggleFollow();
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: reel.isFollowing ? Colors.white12 : AppTheme.hextechCyan,
              foregroundColor: reel.isFollowing ? Colors.white : Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: reel.isFollowing ? Colors.white30 : AppTheme.hextechCyan,
                ),
              ),
            ),
            icon: Icon(reel.isFollowing ? Icons.check_rounded : Icons.add_rounded, size: 18),
            label: Text(
              reel.isFollowing ? _tr('breif_following') : _tr('breif_follow'),
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ),
          const SizedBox(height: 12),

          // Métricas del creador (incluye contador de Vistas Totales)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCreatorStat(
                  _tr('breif_profile_views'),
                  _formatCompactCount(totalViews),
                ),
                _buildCreatorStat(
                  _tr('breif_profile_followers'),
                  _formatCompactCount(followersCount),
                ),
                _buildCreatorStat(
                  _tr('breif_profile_likes'),
                  _formatCompactCount(totalLikes),
                ),
                _buildCreatorStat(
                  _tr('breif_profile_videos'),
                  '$totalVideos',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white12),

          // Grid de videos del creador (tappable para reproducir)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.hextechCyan))
                : reelsList.isEmpty
                    ? Center(
                        child: Text(
                          _tr('breif_profile_empty_creator'),
                          style: GoogleFonts.outfit(color: Colors.white54),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.65,
                        ),
                        itemCount: reelsList.length,
                        itemBuilder: (context, index) {
                          final item = reelsList[index];
                          return GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.black,
                                builder: (_) => _SingleReelPlayerSheet(reel: item),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  border: Border.all(color: Colors.white12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (item.thumbnailUrl.isNotEmpty)
                                      Image.network(
                                        item.thumbnailUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Center(
                                          child: Icon(
                                            Icons.play_circle_outline_rounded,
                                            color: Colors.white.withValues(alpha: 0.4),
                                            size: 30,
                                          ),
                                        ),
                                      )
                                    else
                                      Center(
                                        child: Icon(
                                          Icons.play_circle_outline_rounded,
                                          color: Colors.white.withValues(alpha: 0.4),
                                          size: 30,
                                        ),
                                      ),
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.7),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 6,
                                      left: 6,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.visibility, color: Colors.white70, size: 12),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatCompactCount(item.viewsCount),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5),
        ),
      ],
    );
  }
}

// ==============================================================================
// REPRODUCTOR HORIZONTAL FULLSCREEN (BOTÓN DE ROTACIÓN)
// ==============================================================================

class _LandscapeVideoPlayerPage extends StatefulWidget {
  final ReelModel reel;
  final VideoPlayerController controller;

  const _LandscapeVideoPlayerPage({
    required this.reel,
    required this.controller,
  });

  @override
  State<_LandscapeVideoPlayerPage> createState() => _LandscapeVideoPlayerPageState();
}

class _LandscapeVideoPlayerPageState extends State<_LandscapeVideoPlayerPage> {
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _togglePlayPause() {
    if (!widget.controller.value.isInitialized) return;
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
      } else {
        widget.controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final aspect = c.value.isInitialized && c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showOverlay = !_showOverlay),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(c),
              ),
            ),
            if (_showOverlay) ...[
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${widget.reel.title} • @${widget.reel.creatorUsername}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xCC0B1220),
                          foregroundColor: AppTheme.hextechCyan,
                          side: const BorderSide(color: AppTheme.hextechCyan),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        icon: const Icon(Icons.screen_rotation_rounded, size: 16),
                        label: const Text('Vertical'),
                      ),
                    ],
                  ),
                ),
              ),
              Center(
                child: IconButton(
                  onPressed: _togglePlayPause,
                  iconSize: 64,
                  icon: Icon(
                    c.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: AppTheme.hextechCyan,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// REPRODUCTOR INDIVIDUAL DESDE GRID DE PERFIL
// ==============================================================================

class _SingleReelPlayerSheet extends StatefulWidget {
  final ReelModel reel;

  const _SingleReelPlayerSheet({required this.reel});

  @override
  State<_SingleReelPlayerSheet> createState() => _SingleReelPlayerSheetState();
}

class _SingleReelPlayerSheetState extends State<_SingleReelPlayerSheet> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.reel.videoUrl.isNotEmpty) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.reel.videoUrl))
        ..initialize().then((_) {
          if (!mounted) return;
          _controller?.setLooping(true);
          _controller?.play();
          setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final initialized = c != null && c.value.isInitialized;
    final isLandscape = initialized && c.value.size.width > 0 && c.value.size.height > 0
        ? (c.value.size.width > c.value.size.height * 1.05)
        : widget.reel.isLandscape;
    final aspect = initialized && c.value.aspectRatio > 0 ? c.value.aspectRatio : (isLandscape ? 16 / 9 : 9 / 16);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (initialized)
            GestureDetector(
              onTap: () {
                setState(() {
                  if (c.value.isPlaying) {
                    c.pause();
                  } else {
                    c.play();
                  }
                });
              },
              child: isLandscape
                  ? Center(child: AspectRatio(aspectRatio: aspect, child: VideoPlayer(c)))
                  : FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: c.value.size.width,
                        height: c.value.size.height,
                        child: VideoPlayer(c),
                      ),
                    ),
            )
          else
            const Center(child: CircularProgressIndicator(color: AppTheme.hextechCyan)),
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.reel.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                      ),
                    ),
                  ),
                  if (initialized && isLandscape)
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => _LandscapeVideoPlayerPage(reel: widget.reel, controller: c),
                          ),
                        );
                      },
                      icon: const Icon(Icons.screen_rotation_rounded, color: AppTheme.hextechCyan),
                      tooltip: 'Ver en horizontal',
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          if (initialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: AppTheme.hextechCyan,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==============================================================================
// LINKS SOCIALES DEL CREADOR (TWITCH, TIKTOK, YOUTUBE, INSTAGRAM, KICK)
// ==============================================================================

class _SocialLinksRow extends StatelessWidget {
  final CreatorSocialProfile profile;

  const _SocialLinksRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, dynamic>>[
      if (profile.twitchUrl.isNotEmpty)
        {'label': 'Twitch', 'url': profile.twitchUrl, 'color': const Color(0xFF9146FF), 'icon': Icons.live_tv_rounded},
      if (profile.tiktokUrl.isNotEmpty)
        {'label': 'TikTok', 'url': profile.tiktokUrl, 'color': const Color(0xFFFF0050), 'icon': Icons.music_note_rounded},
      if (profile.youtubeUrl.isNotEmpty)
        {'label': 'YouTube', 'url': profile.youtubeUrl, 'color': const Color(0xFFFF0000), 'icon': Icons.play_arrow_rounded},
      if (profile.kickUrl.isNotEmpty)
        {'label': 'Kick', 'url': profile.kickUrl, 'color': const Color(0xFF53FC18), 'icon': Icons.bolt_rounded},
      if (profile.instagramUrl.isNotEmpty)
        {'label': 'Instagram', 'url': profile.instagramUrl, 'color': const Color(0xFFE1306C), 'icon': Icons.camera_alt_rounded},
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: items.map((item) {
        final color = item['color'] as Color;
        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            NativeService.openExternalUrl(item['url'] as String);
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.7)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item['icon'] as IconData, color: color, size: 14),
                const SizedBox(width: 5),
                Text(
                  item['label'] as String,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 11),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ==============================================================================
// MODAL EDITAR PERFIL DE CREADOR (BIO + TWITCH / TIKTOK / REDES)
// ==============================================================================

class _EditCreatorProfileDialog extends StatefulWidget {
  final CreatorSocialProfile initial;

  const _EditCreatorProfileDialog({required this.initial});

  @override
  State<_EditCreatorProfileDialog> createState() => _EditCreatorProfileDialogState();
}

class _EditCreatorProfileDialogState extends State<_EditCreatorProfileDialog> {
  late final TextEditingController _bioCtrl;
  late final TextEditingController _twitchCtrl;
  late final TextEditingController _tiktokCtrl;
  late final TextEditingController _youtubeCtrl;
  late final TextEditingController _kickCtrl;
  late final TextEditingController _instagramCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bioCtrl = TextEditingController(text: widget.initial.bio);
    _twitchCtrl = TextEditingController(text: widget.initial.twitchUrl);
    _tiktokCtrl = TextEditingController(text: widget.initial.tiktokUrl);
    _youtubeCtrl = TextEditingController(text: widget.initial.youtubeUrl);
    _kickCtrl = TextEditingController(text: widget.initial.kickUrl);
    _instagramCtrl = TextEditingController(text: widget.initial.instagramUrl);
  }

  @override
  void dispose() {
    _bioCtrl.dispose();
    _twitchCtrl.dispose();
    _tiktokCtrl.dispose();
    _youtubeCtrl.dispose();
    _kickCtrl.dispose();
    _instagramCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await ReelsService.updateCreatorProfile(
        bio: _bioCtrl.text.trim(),
        twitchUrl: _twitchCtrl.text.trim(),
        tiktokUrl: _tiktokCtrl.text.trim(),
        youtubeUrl: _youtubeCtrl.text.trim(),
        kickUrl: _kickCtrl.text.trim(),
        instagramUrl: _instagramCtrl.text.trim(),
      );
      if (mounted) {
        AppSnackBar.showSuccess(context, 'Perfil actualizado correctamente');
        Navigator.of(context).pop(updated);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnackBar.showError(
          context,
          e is ApiException ? e.message : 'No se pudo guardar el perfil',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Editar Perfil de Creador',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  TextField(
                    controller: _bioCtrl,
                    maxLines: 3,
                    maxLength: 220,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: const InputDecoration(
                      labelText: 'Descripción / Bio',
                      hintText: 'Cuéntale a la comunidad qué juegas o cuándo haces directo...',
                      labelStyle: TextStyle(color: Colors.white70),
                      hintStyle: TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLinkField(_twitchCtrl, 'Twitch', 'https://twitch.tv/tu_canal', Icons.live_tv_rounded),
                  const SizedBox(height: 10),
                  _buildLinkField(_tiktokCtrl, 'TikTok', 'https://tiktok.com/@tu_usuario', Icons.music_note_rounded),
                  const SizedBox(height: 10),
                  _buildLinkField(_youtubeCtrl, 'YouTube', 'https://youtube.com/@tu_canal', Icons.play_arrow_rounded),
                  const SizedBox(height: 10),
                  _buildLinkField(_kickCtrl, 'Kick', 'https://kick.com/tu_canal', Icons.bolt_rounded),
                  const SizedBox(height: 10),
                  _buildLinkField(_instagramCtrl, 'Instagram', 'https://instagram.com/tu_usuario', Icons.camera_alt_rounded),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.hextechCyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                      )
                    : const Text('Guardar cambios', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkField(TextEditingController ctrl, String label, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.url,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.hextechCyan, size: 19),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

// ==============================================================================
// MODAL SOLICITUD DE RETIRO ($100 USD MÍNIMO) E HISTORIAL
// ==============================================================================

class _PayoutRequestDialog extends StatefulWidget {
  final UserReelsStats stats;

  const _PayoutRequestDialog({required this.stats});

  @override
  State<_PayoutRequestDialog> createState() => _PayoutRequestDialogState();
}

class _PayoutRequestDialogState extends State<_PayoutRequestDialog> {
  final TextEditingController _destCtrl = TextEditingController();
  String _method = 'paypal';
  bool _submitting = false;
  bool _loadingHistory = true;
  List<CreatorPayoutModel> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _destCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final list = await ReelsService.getMyPayouts();
      if (mounted) {
        setState(() {
          _history = list;
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _submit() async {
    final dest = _destCtrl.text.trim();
    if (dest.length < 4) {
      AppSnackBar.showError(context, 'Ingresa un correo o cuenta válida para el pago');
      return;
    }
    setState(() => _submitting = true);
    try {
      final msg = await ReelsService.requestPayout(
        payoutMethod: _method,
        payoutDestination: dest,
      );
      if (mounted) {
        AppSnackBar.showSuccess(context, msg);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        AppSnackBar.showError(
          context,
          e is ApiException ? e.message : 'No se pudo procesar la solicitud de retiro',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.74,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Monetización y Retiros',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.hextechGold.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Disponible: \$${stats.availableBalanceUsd.toStringAsFixed(4)} USD',
                    style: GoogleFonts.outfit(color: AppTheme.hextechGold, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vistas verificadas históricas: ${_formatCompactCount(stats.lifetimeVerifiedViews)} • Tarifa: \$0.01 / 1,000 vistas',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5),
                  ),
                  if (stats.pendingPayoutUsd > 0 || stats.paidOutUsd > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Pendiente: \$${stats.pendingPayoutUsd.toStringAsFixed(2)} • Pagado: \$${stats.paidOutUsd.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (stats.canWithdraw) ...[
              Wrap(
                spacing: 8,
                children: ['paypal', 'wise', 'binance', 'bank'].map((m) {
                  final selected = _method == m;
                  return ChoiceChip(
                    label: Text(m.toUpperCase()),
                    selected: selected,
                    onSelected: (_) => setState(() => _method = m),
                    selectedColor: AppTheme.hextechCyan,
                    labelStyle: TextStyle(
                      color: selected ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _destCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: const InputDecoration(
                  labelText: 'Correo o cuenta destino',
                  hintText: 'Ej: tu-correo@paypal.com / Binance ID / Cuenta',
                  labelStyle: TextStyle(color: Colors.white70),
                  hintStyle: TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.hextechGold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                        )
                      : Text(
                          'Solicitar retiro de \$${stats.availableBalanceUsd.toStringAsFixed(2)} USD',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ] else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Alcanza el mínimo de \$${stats.minPayoutUsd.toStringAsFixed(0)} USD en vistas verificadas (90% reproducido, 1 vista única por usuario) para habilitar el botón de retiro.',
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            Text(
              'Historial de retiros',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loadingHistory
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.hextechCyan))
                  : _history.isEmpty
                      ? Center(
                          child: Text(
                            'Aún no tienes solicitudes de retiro.',
                            style: GoogleFonts.inter(color: Colors.white54, fontSize: 12.5),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _history.length,
                          separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                          itemBuilder: (_, idx) {
                            final item = _history[idx];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '\$${item.amountUsd.toStringAsFixed(2)} USD • ${item.payoutMethod.toUpperCase()}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              subtitle: Text(
                                item.payoutDestination,
                                style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                              ),
                              trailing: Text(
                                item.status.toUpperCase(),
                                style: TextStyle(
                                  color: item.status == 'paid'
                                      ? AppTheme.hextechEmerald
                                      : item.status == 'rejected'
                                          ? AppTheme.hextechCrimson
                                          : AppTheme.hextechGold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
