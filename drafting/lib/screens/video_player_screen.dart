import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models/video_model.dart';
import '../core/services/video_service.dart';
import '../core/services/finance_service.dart';
import '../core/services/interaction_service.dart';
import '../core/services/api_client.dart';
import '../theme/app_theme.dart';
import 'economy_screen.dart';
import 'edit_video_screen.dart';

class VideoPlayerScreen extends StatefulWidget {
  final VideoModel video;

  const VideoPlayerScreen({
    super.key, 
    required this.video,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late YoutubePlayerController _controller;
  bool _isLiked = false;
  
  bool _isOwner = false;
  String? _currentUserId;
  
  Timer? _viewTimer;
  bool _viewCounted = false;

  bool _isSubscribed = false;
  bool _notificationsEnabled = false;
  int _totalSubscribers = 0;

  int _pendingDonations = 0;
  Timer? _donationTimer;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.video.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
    
    _checkSubStatus();
    _startViewTimer();
    _checkOwner();
  }

  void _checkOwner() async {
    try {
      final authRes = await ApiClient.get('/api/v1/auth/me', authenticated: true);
      if (authRes.statusCode == 200) {
        if (mounted) setState(() => _currentUserId = jsonDecode(authRes.body)['id']);
      }
      final chanRes = await ApiClient.get('/content/channel/me', authenticated: true);
      if (chanRes.statusCode == 200) {
        final chanData = jsonDecode(chanRes.body);
        if (mounted && chanData['id'] == widget.video.channelId) {
          setState(() => _isOwner = true);
        }
      }
    } catch (e) {}
  }

  void _checkSubStatus() async {
    final status = await InteractionService().getSubscriptionStatus(widget.video.channelId);
    if (mounted) {
      setState(() {
        _isSubscribed = status['is_subscribed'];
        _notificationsEnabled = status['notifications_enabled'];
        _totalSubscribers = status['total_subscribers'];
      });
    }
  }

  void _startViewTimer() {
    _viewTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_viewCounted) {
        InteractionService().incrementView(widget.video.id);
        _viewCounted = true;
      }
    });
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    _donationTimer?.cancel();
    _controller.close();
    super.dispose();
  }

  Future<void> _handleLike() async {
    final result = await InteractionService().toggleVideoLike(widget.video.id);
    if (mounted) {
      setState(() {
        _isLiked = result['is_liked'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final relatedVideos = VideoService().videos.where((v) => v.videoId != widget.video.videoId).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: AppTheme.surface,
            onSelected: (value) async {
              if (value == 'report') {
                _showReportDialog(context);
              } else if (value == 'edit') {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => EditVideoScreen(video: widget.video)),
                );
                if (result == true) {
                  // If video was updated, we might need to refresh or show a success message
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video actualizado')));
                }
              } else if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppTheme.surface,
                    title: const Text('Eliminar Video', style: TextStyle(color: Colors.white)),
                    content: const Text('¿Estás seguro de que quieres eliminar este video?', style: TextStyle(color: AppTheme.textMuted)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Eliminar')),
                    ],
                  ),
                );
                if (confirm == true) {
                  final success = await VideoService().deleteVideo(widget.video.id);
                  if (mounted) {
                    if (success) {
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al eliminar el video')));
                    }
                  }
                }
              }
            },
            itemBuilder: (context) => [
              if (_isOwner) ...[
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Editar Video'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Eliminar Video', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
              const PopupMenuItem(
                value: 'report',
                child: Text('Reportar Video', style: TextStyle(color: Colors.orangeAccent)),
              ),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          YoutubePlayer(controller: _controller),
          Expanded(
            child: Container(
              color: AppTheme.background,
              child: ListView(
                padding: const EdgeInsets.all(20.0),
                children: [
                  // Title and Views
                  Text(
                    widget.video.title,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_formatCount(widget.video.views + (_viewCounted ? 1 : 0))} vistas • ${widget.video.createdAt.day}/${widget.video.createdAt.month}/${widget.video.createdAt.year} • ${_formatCount(widget.video.likes)} likes',
                    style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  
                  Wrap(
                    spacing: 8,
                    children: widget.video.tags.map((tag) => Text(
                      '#$tag',
                      style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.w600),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildActionItem(
                        icon: _isLiked ? Icons.thumb_up : Icons.thumb_up_outlined, 
                        label: 'Me gusta', 
                        isActive: _isLiked,
                        onTap: _handleLike,
                      ),
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          _buildActionItem(
                            icon: Icons.monetization_on_outlined, 
                            label: 'Donar',
                            onTap: _handleRapidDonate,
                          ),
                          if (_pendingDonations > 0)
                            Positioned(
                              top: -15,
                              child: AnimatedScale(
                                scale: _pendingDonations > 0 ? 1.1 : 0.0,
                                duration: const Duration(milliseconds: 150),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'x$_pendingDonations',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      _buildActionItem(
                        icon: Icons.share_outlined, 
                        label: 'Compartir',
                        onTap: () {
                          Share.share('¡Mira el increíble video "${widget.video.title}" en Drafting!\n\nDescarga la app para apoyar a tus creadores favoritos: https://drafting.app');
                        }
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: NetworkImage(widget.video.channelAvatar),
                        radius: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(widget.video.channelName, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                                if (widget.video.isChannelVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, color: Colors.blueAccent, size: 16),
                                ]
                              ],
                            ),
                            Text('$_totalSubscribers suscriptores', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (_isSubscribed)
                        IconButton(
                          icon: Icon(
                            _notificationsEnabled ? Icons.notifications_active : Icons.notifications_none,
                            color: _notificationsEnabled ? AppTheme.primary : AppTheme.textMuted,
                          ),
                          onPressed: () async {
                            final res = await InteractionService().toggleSubscription(widget.video.channelId, notify: true);
                            setState(() {
                              _isSubscribed = res['is_subscribed'];
                              _notificationsEnabled = res['notifications_enabled'];
                              _totalSubscribers = res['total_subscribers'];
                            });
                          },
                        ),
                      ElevatedButton(
                        onPressed: () async {
                          final res = await InteractionService().toggleSubscription(widget.video.channelId);
                          setState(() {
                            _isSubscribed = res['is_subscribed'];
                            _notificationsEnabled = res['notifications_enabled'];
                            _totalSubscribers = res['total_subscribers'];
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSubscribed ? AppTheme.surface : Colors.white,
                          foregroundColor: _isSubscribed ? Colors.white : Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        ),
                        child: Text(_isSubscribed ? 'Suscrito' : 'Suscribirse', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.video.description,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),

                  GestureDetector(
                    onTap: _showCommentsBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Comentarios', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              const Icon(Icons.unfold_more, color: Colors.white),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Toca para ver o añadir comentarios...',
                            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Related Videos
                  Text('Videos relacionados', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ...relatedVideos.map((related) => _buildRelatedVideoTile(related)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem({required IconData icon, required String label, bool isActive = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: isActive ? AppTheme.primary : Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(color: isActive ? AppTheme.primary : Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildRelatedVideoTile(VideoModel related) {
    return InkWell(
      onTap: () {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: related)));
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: 'https://img.youtube.com/vi/${related.videoId}/hqdefault.jpg',
                width: 140,
                height: 80,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(width: 140, height: 80, color: AppTheme.surface),
                errorWidget: (context, url, error) => Container(width: 140, height: 80, color: AppTheme.surface, child: const Icon(Icons.error, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    related.title,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    related.channelName,
                    style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    related.viewsAndDate,
                    style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    String reason = 'Contenido Inapropiado';
    final proofController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text('Reportar Video', style: GoogleFonts.outfit(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    items: ['Contenido Inapropiado', 'Spam', 'Falsificación de identidad']
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => reason = val);
                    },
                  ),
                  if (reason == 'Falsificación de identidad') ...[
                    const SizedBox(height: 16),
                    Text(
                      'Por favor, pega un enlace (YouTube, Google Drive) de un video corto donde muestres tu rostro y digas: "Hola, soy el creador real de este video y quiero reportar esta copia en Drafting".',
                      style: GoogleFonts.inter(color: Colors.orangeAccent, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: proofController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'URL de prueba',
                        hintStyle: TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: AppTheme.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (reason == 'Falsificación de identidad' && proofController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debes proveer una URL de prueba')));
                    return;
                  }
                  
                  // Call API
                  try {
                    await ApiClient.post(
                      '/moderation/report',
                      authenticated: true,
                      body: {
                        'video_id': widget.video.id,
                        'reason': reason,
                        'proof_url': proofController.text.trim(),
                      }
                    );
                    if (mounted) Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reporte enviado con éxito')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al enviar el reporte')));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Enviar Reporte', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    ).then((_) => proofController.dispose());
  }

  void _handleRapidDonate() {
    setState(() {
      _pendingDonations++;
    });

    _donationTimer?.cancel();
    _donationTimer = Timer(const Duration(seconds: 1), () async {
      final amount = _pendingDonations;
      if (amount == 0) return;
      
      setState(() {
        _pendingDonations = 0;
      });

      final success = await FinanceService().donateToVideo(widget.video.id, amount.toDouble());

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Has donado $amount esencias azules a ${widget.video.channelName}!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fondos insuficientes o error en el sistema.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  void _showCommentsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return CommentsBottomSheet(videoId: widget.video.id, currentUserId: _currentUserId);
      },
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

class CommentsBottomSheet extends StatefulWidget {
  final String videoId; // Treat as contentId
  final String? currentUserId;
  final String contentType;

  const CommentsBottomSheet({super.key, required this.videoId, this.currentUserId, this.contentType = 'video'});

  @override
  State<CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<CommentsBottomSheet> {
  final _commentController = TextEditingController();
  String? _replyingToId;
  String? _replyingToName;

  @override
  void initState() {
    super.initState();
    InteractionService().fetchComments(widget.videoId, contentType: widget.contentType).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final success = await InteractionService().postComment(
      widget.videoId,
      text,
      parentId: _replyingToId,
      contentType: widget.contentType,
    );

    if (success && mounted) {
      _commentController.clear();
      setState(() {
        _replyingToId = null;
        _replyingToName = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = InteractionService();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Comentarios',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),
            const Divider(color: Colors.white12),
            Expanded(
              child: service.isLoadingComments
                  ? const Center(child: CircularProgressIndicator())
                  : service.topLevelComments.isEmpty
                      ? Center(child: Text('Sé el primero en comentar', style: TextStyle(color: AppTheme.textMuted)))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: service.topLevelComments.length,
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, index) {
                            final comment = service.topLevelComments[index];
                            final replies = service.getReplies(comment.id);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCommentItem(comment),
                                if (replies.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 40, top: 8),
                                    child: Column(
                                      children: replies.map((reply) => Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: _buildCommentItem(reply, isReply: true),
                                      )).toList(),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                              ],
                            );
                          },
                        ),
            ),
            if (_replyingToName != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppTheme.primary.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Text('Respondiendo a $_replyingToName', style: TextStyle(color: AppTheme.primary, fontSize: 12)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() {
                        _replyingToId = null;
                        _replyingToName = null;
                      }),
                      child: const Icon(Icons.close, size: 16, color: AppTheme.primary),
                    )
                  ],
                ),
              ),
            Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 16, right: 16, top: 16
              ),
              decoration: const BoxDecoration(
                color: AppTheme.background,
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Añade un comentario...',
                        hintStyle: const TextStyle(color: AppTheme.textMuted),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppTheme.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppTheme.primary),
                    onPressed: _postComment,
                  )
                ],
              ),
            )
          ],
        );
      },
    );
  }

  Widget _buildCommentItem(CommentModel comment, {bool isReply = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: isReply ? 12 : 16,
          backgroundImage: NetworkImage(comment.authorAvatar),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(comment.authorName, style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12)),
                  const SizedBox(width: 8),
                  Text(_timeAgo(comment.createdAt), style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 10)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                comment.content,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (!isReply)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _replyingToId = comment.id;
                          _replyingToName = comment.authorName;
                        });
                      },
                      child: Text('Responder', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  if (widget.currentUserId != null && comment.userId == widget.currentUserId) ...[
                    if (!isReply) const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _editComment(comment),
                      child: Text('Editar', style: GoogleFonts.inter(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _deleteComment(comment.id),
                      child: Text('Eliminar', style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ]
                ],
              ),
            ],
          ),
        )
      ],
    );
  }

  void _editComment(CommentModel comment) {
    final editController = TextEditingController(text: comment.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Editar Comentario', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: editController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(filled: true, fillColor: AppTheme.background),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await InteractionService().updateComment(comment.id, editController.text);
              if (success && mounted) setState(() {});
            },
            child: const Text('Guardar'),
          )
        ],
      ),
    );
  }

  void _deleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Eliminar Comentario', style: TextStyle(color: Colors.white)),
        content: const Text('¿Eliminar este comentario?', style: TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm == true) {
      final success = await InteractionService().deleteComment(commentId);
      if (success && mounted) setState(() {});
    }
  }

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return 'hace ${diff.inDays} d';
    if (diff.inHours > 0) return 'hace ${diff.inHours} h';
    if (diff.inMinutes > 0) return 'hace ${diff.inMinutes} m';
    return 'justo ahora';
  }
}
