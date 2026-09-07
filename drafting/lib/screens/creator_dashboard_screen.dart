import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/video_model.dart';
import '../core/models/fanart_model.dart';
import '../core/services/video_service.dart';
import '../core/services/fanart_service.dart';
import '../core/services/creator_service.dart';
import '../theme/app_theme.dart';
import 'edit_channel_screen.dart';
import 'creator_setup_screen.dart';
import 'video_player_screen.dart';
import 'finance_dashboard_screen.dart';
import 'edit_video_screen.dart';
import 'upload_video_screen.dart';
import 'upload_fanart_screen.dart';
import 'creator_setup_screen.dart';
import 'fanart_detail_screen.dart';

class CreatorDashboardScreen extends StatefulWidget {
  const CreatorDashboardScreen({super.key});

  @override
  State<CreatorDashboardScreen> createState() => _CreatorDashboardScreenState();
}

class _CreatorDashboardScreenState extends State<CreatorDashboardScreen> {
  bool _isLoading = true;
  List<VideoModel> _myVideos = [];
  List<FanartModel> _myFanarts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await VideoService().fetchMyChannel();
    _myVideos = await VideoService().fetchMyVideos();
    _myFanarts = await FanartService().fetchMyFanarts();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final channel = VideoService().currentUserChannel;
    if (channel == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('Creator Studio', style: GoogleFonts.outfit(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Aún no tienes un canal.', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatorSetupScreen(isForVideo: true)));
                  _loadData();
                },
                child: Text('Crear Canal', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('Creator Studio', style: GoogleFonts.outfit(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_balance_wallet, color: Colors.greenAccent),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceDashboardScreen()));
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const EditChannelScreen()));
                _loadData(); // Reload after edit
              },
            )
          ],
          bottom: const TabBar(
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.primary,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(text: 'Mis Videos'),
              Tab(text: 'Mis FanArts'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileHeader(channel),
                  const SizedBox(height: 24),
                  _buildStatsRow(channel),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Mis Videos',
                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMyVideosList(),
                ],
              ),
            ),
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Mis FanArts',
                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMyFanartsList(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: AppTheme.primary,
          child: const Icon(Icons.add, color: Colors.white),
          onPressed: _showUploadMenu,
        ),
      ),
    );
  }

  Widget _buildProfileHeader(ChannelModel channel) {
    return Column(
      children: [
        // Banner
        Container(
          height: 120,
          width: double.infinity,
          color: AppTheme.surface,
          child: channel.bannerUrl.isNotEmpty
              ? Image.network(channel.bannerUrl, fit: BoxFit.cover, errorBuilder: (_,_,_) => const SizedBox())
              : const Center(child: Icon(Icons.image, color: Colors.white24, size: 40)),
        ),
        // Avatar & Info
        Transform.translate(
          offset: const Offset(0, -40),
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppTheme.background,
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: channel.channelAvatar.isNotEmpty 
                      ? NetworkImage(channel.channelAvatar) 
                      : null,
                  backgroundColor: AppTheme.surface,
                  child: channel.channelAvatar.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                channel.channelName,
                style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  channel.description.isNotEmpty ? channel.description : 'Sin descripción',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(ChannelModel channel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(child: _buildStatCard('Suscriptores', channel.totalSubscribers.toString())),
          const SizedBox(width: 16),
          Expanded(child: _buildStatCard('Vistas Totales', channel.totalViews.toString())),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMyVideosList() {
    if (_myVideos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text('Aún no has subido ningún video.', style: GoogleFonts.inter(color: AppTheme.textMuted)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _myVideos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final video = _myVideos[index];
        final thumbnailUrl = 'https://img.youtube.com/vi/${video.videoId}/mqdefault.jpg';
        
        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(
                  video: video, 
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(thumbnailUrl, width: 100, height: 60, fit: BoxFit.cover, errorBuilder: (_,_,_) => Container(width: 100, height: 60, color: Colors.black)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(video.title, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('${video.views} vistas • ${video.createdAt.day}/${video.createdAt.month}/${video.createdAt.year}', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
                  color: AppTheme.surface,
                  onSelected: (value) async {
                    if (value == 'edit') {
                      final changed = await Navigator.push(context, MaterialPageRoute(builder: (_) => EditVideoScreen(video: video)));
                      if (changed == true) {
                        _loadData();
                      }
                    } else if (value == 'delete') {
                      _showDeleteConfirmation(video.id);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Editar', style: TextStyle(color: Colors.white)),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Borrar', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(String videoId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Borrar Video', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text('¿Estás seguro de que quieres borrar este video? Esta acción no se puede deshacer.', style: GoogleFonts.inter(color: AppTheme.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              await VideoService().deleteVideo(videoId);
              _loadData();
            },
            child: const Text('Borrar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildMyFanartsList() {
    if (_myFanarts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text('Aún no has subido ningún FanArt.', style: GoogleFonts.inter(color: AppTheme.textMuted)),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _myFanarts.length,
      itemBuilder: (context, index) {
        final fanart = _myFanarts[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FanartDetailScreen(fanart: fanart)),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Image.network(
                      fanart.imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Colors.black26),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          fanart.title,
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 18),
                        color: AppTheme.surface,
                        onSelected: (value) {
                          if (value == 'delete') {
                            _showDeleteFanartConfirmation(fanart.id);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Borrar', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteFanartConfirmation(String fanartId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Borrar FanArt', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text('¿Estás seguro de que quieres borrar este FanArt? Esta acción no se puede deshacer.', style: GoogleFonts.inter(color: AppTheme.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              await FanartService().deleteFanart(fanartId);
              _loadData();
            },
            child: const Text('Borrar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showUploadMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Crear Contenido', style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.video_library, color: Colors.white)),
                  title: Text('Subir Video', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('Comparte guías y gameplays.', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13)),
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadVideoScreen()));
                    _loadData();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.purpleAccent, child: Icon(Icons.brush, color: Colors.white)),
                  title: Text('Subir FanArt', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('Monetiza tu arte con la comunidad.', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13)),
                  onTap: () async {
                    Navigator.pop(context);
                    // Check if Creator Space exists
                    setState(() => _isLoading = true);
                    final profile = await CreatorService().getCreatorProfile();
                    
                    if (!mounted) return;
                    
                    if (profile != null) {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadFanartScreen()));
                      _loadData();
                    } else {
                      setState(() => _isLoading = false);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatorSetupScreen()));
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
}
