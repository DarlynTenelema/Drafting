import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../core/models/video_model.dart';
import '../core/services/video_service.dart';
import '../theme/app_theme.dart';
import 'video_player_screen.dart';
import 'upload_video_screen.dart';
import 'create_channel_screen.dart';
import 'search_screen.dart';
import 'creator_dashboard_screen.dart';
import '../widgets/app_drawer.dart';
import '../widgets/report_dialog.dart';

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch videos when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VideoService().fetchVideos();
    });
  }

  void _onAddVideoPressed() {
    if (VideoService().currentUserChannel == null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateChannelScreen()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadVideoScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        title: Text(
          'Videos',
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatorDashboardScreen()));
            },
            icon: const Icon(Icons.dashboard_customize, color: Colors.white),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
            },
            icon: const Icon(Icons.search, color: Colors.white),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60.0),
        child: FloatingActionButton(
          heroTag: 'add_video',
          onPressed: _onAddVideoPressed,
          backgroundColor: AppTheme.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: VideoService(),
                builder: (context, child) {
                  final videoService = VideoService();
                  if (videoService.isLoading) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                  }
                  
                  final videos = videoService.videos;
                  if (videos.isEmpty) {
                    return const Center(
                      child: Text('Aún no hay videos disponibles.', style: TextStyle(color: Colors.white70)),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: videos.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 24),
                    itemBuilder: (context, index) {
                      return VideoCard(video: videos[index]);
                    },
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

class VideoCard extends StatefulWidget {
  final VideoModel video;
  const VideoCard({super.key, required this.video});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _playVideo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          video: widget.video, 
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // High-res YouTube thumbnail URL
    final thumbnailUrl = 'https://img.youtube.com/vi/${widget.video.videoId}/hqdefault.jpg';

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        _playVideo();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(scale: _scaleAnimation.value, child: child),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with Play Button
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: AppTheme.surface),
                      errorWidget: (context, url, error) => Container(
                        color: AppTheme.surface,
                        child: const Icon(Icons.error, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                // Glassmorphism Play Button
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Channel Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: widget.video.channelAvatar.startsWith('http') 
                      ? NetworkImage(widget.video.channelAvatar) 
                      : FileImage(File(widget.video.channelAvatar)) as ImageProvider,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.video.title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.video.channelName} • ${widget.video.viewsAndDate}',
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: AppTheme.surface,
                      builder: (context) {
                        return SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.share, color: Colors.white),
                                title: const Text('Compartir', style: TextStyle(color: Colors.white)),
                                onTap: () {
                                  Navigator.pop(context);
                                  Share.share('¡Mira este video! https://youtube.com/watch?v=${widget.video.videoId}');
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.report, color: Colors.redAccent),
                                title: const Text('Reportar', style: TextStyle(color: Colors.redAccent)),
                                onTap: () {
                                  Navigator.pop(context);
                                  showDialog(
                                    context: context,
                                    builder: (context) => ReportDialog(videoId: widget.video.id),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}
