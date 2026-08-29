import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
// import 'package:screen_protector/screen_protector.dart';
import 'dart:convert';
import '../theme/app_theme.dart';
import '../core/models/fanart_model.dart';
import '../core/services/fanart_service.dart';
import '../core/services/api_client.dart';
import 'video_player_screen.dart';

class FanartDetailScreen extends StatefulWidget {
  final FanartModel fanart;

  const FanartDetailScreen({super.key, required this.fanart});

  @override
  State<FanartDetailScreen> createState() => _FanartDetailScreenState();
}

class _FanartDetailScreenState extends State<FanartDetailScreen> {
  bool _isLiked = false;
  int _likes = 0;
  bool _isPurchased = false;
  
  bool _isOwner = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _likes = widget.fanart.likes;
    _checkStatus();
    _secureScreen();
    _checkOwner();
  }

  void _checkOwner() async {
    try {
      final authRes = await ApiClient.get('/api/v1/auth/me', authenticated: true);
      if (authRes.statusCode == 200) {
        final data = jsonDecode(authRes.body);
        if (mounted) setState(() {
          _currentUserId = data['id'];
          if (widget.fanart.creatorId == _currentUserId) _isOwner = true;
        });
      }
    } catch(e) {}
  }

  Future<void> _checkStatus() async {
    final isPurchased = await FanartService().checkPurchase(widget.fanart.id);
    if (mounted) {
      setState(() {
        _isPurchased = isPurchased;
      });
    }
  }

  Future<void> _secureScreen() async {
    // await ScreenProtector.preventScreenshotOn();
  }

  Future<void> _unsecureScreen() async {
    // await ScreenProtector.preventScreenshotOff();
  }

  @override
  void dispose() {
    _unsecureScreen();
    super.dispose();
  }

  void _showCommentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return CommentsBottomSheet(
          videoId: widget.fanart.id, 
          currentUserId: _currentUserId, 
          contentType: 'fanart',
        );
      },
    );
  }

  Future<void> _downloadToGallery() async {
    final hasAccess = await Gal.hasAccess(toAlbum: true);
    if (!hasAccess) {
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso denegado para guardar en galería.'), backgroundColor: Colors.red),
          );
        }
        return;
      }
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    try {
      final appDocDir = await getTemporaryDirectory();
      final savePath = '${appDocDir.path}/${widget.fanart.id}.jpg';
      await Dio().download(widget.fanart.imageUrl, savePath);
      await Gal.putImage(savePath);
      
      if (!mounted) return;
      Navigator.pop(context); // pop loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagen guardada en la galería.'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // pop loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al descargar: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _handleDownload() async {
    if (_isPurchased) {
      _downloadToGallery();
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Descargar Imagen',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '¿Deseas desbloquear esta imagen por ${widget.fanart.priceCoin.toInt()} Esencias Azules?',
          style: GoogleFonts.inter(color: AppTheme.textLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              // Mostrar indicador de carga
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              );

              final result = await FanartService().purchaseFanart(widget.fanart.id);
              
              if (!mounted) return;
              Navigator.pop(context); // quitar loading

              if (result['success']) {
                setState(() {
                  _isPurchased = true;
                });
                _downloadToGallery();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result['message']), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary, // Blue tint
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Comprar y Descargar',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background for image viewing
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: AppTheme.surface,
            onSelected: (value) async {
              if (value == 'report') {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reporte enviado a moderación')));
              } else if (value == 'edit') {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Editar FanArt (Próximamente)')));
              } else if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppTheme.surface,
                    title: const Text('Eliminar FanArt', style: TextStyle(color: Colors.white)),
                    content: const Text('¿Estás seguro de que quieres eliminar este FanArt?', style: TextStyle(color: AppTheme.textMuted)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Eliminar')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ApiClient.delete('/api/v1/content/fanart?id=${widget.fanart.id}', authenticated: true);
                  if (mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (context) => [
              if (_isOwner) ...[
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Editar FanArt'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Eliminar FanArt', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
              const PopupMenuItem(
                value: 'report',
                child: Text('Reportar', style: TextStyle(color: Colors.orangeAccent)),
              ),
            ],
          )
        ],
      ),
      body: Stack(
        children: [
          // Full Image
          Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: widget.fanart.imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const CircularProgressIndicator(color: AppTheme.primary),
                errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
              ),
            ),
          ),

          // Bottom Controls (Glassmorphism)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Creator & Title
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: NetworkImage(widget.fanart.creatorAvatar),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.fanart.title,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  widget.fanart.creatorName,
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textMuted,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked ? Colors.red : Colors.white,
                            label: _likes > 0 ? '$_likes' : 'Me gusta',
                            onTap: () async {
                              setState(() {
                                _isLiked = !_isLiked;
                                _likes += _isLiked ? 1 : -1;
                              });
                              final res = await FanartService().toggleLike(widget.fanart.id);
                              if (mounted) {
                                setState(() {
                                  _isLiked = res['is_liked'];
                                  _likes = res['total_likes'];
                                });
                              }
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.chat_bubble_outline,
                            color: Colors.white,
                            label: 'Comentar',
                            onTap: _showCommentSheet,
                          ),
                          _buildActionButton(
                            icon: Icons.share_outlined,
                            color: Colors.white,
                            label: 'Compartir',
                            onTap: () {
                              Share.share('¡Mira este increíble Fanart: ${widget.fanart.imageUrl}');
                            },
                          ),
                          // Download Button
                          GestureDetector(
                            onTap: _handleDownload,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                children: [
                                  if (!_isPurchased)
                                    Image.asset('assets/images/crystal_coin_outline.png', width: 20, height: 20),
                                  if (!_isPurchased)
                                    const SizedBox(width: 8),
                                  Text(
                                    _isPurchased ? 'Descargar' : '${widget.fanart.priceCoin.toInt()} Comprar',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
