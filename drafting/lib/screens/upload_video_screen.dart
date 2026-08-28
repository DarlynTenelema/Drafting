import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/video_model.dart';
import '../core/services/video_service.dart';
import '../theme/app_theme.dart';
import 'verification_screen.dart';

class UploadVideoScreen extends StatefulWidget {
  const UploadVideoScreen({super.key});

  @override
  State<UploadVideoScreen> createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends State<UploadVideoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  
  bool _isPublishing = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _publishVideo() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isPublishing = true);

      String url = _urlController.text.trim();
      String videoId = '';
      if (url.contains('v=')) {
        videoId = url.split('v=')[1].split('&')[0];
      } else if (url.contains('youtu.be/')) {
        videoId = url.split('youtu.be/')[1].split('?')[0];
      } else {
        videoId = url; 
      }

      final channel = VideoService().currentUserChannel;
      
      if (channel == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No tienes un canal creado.')),
        );
        setState(() => _isPublishing = false);
        return;
      }

      final newVideo = VideoModel(
        id: '',
        videoId: videoId,
        channelId: channel.id!,
        title: '', // Backend will fill this using YT API
        description: '', // Backend will fill this using YT API
        tags: [], // Backend will fill this using YT API
        channelName: channel.channelName,
        channelAvatar: channel.channelAvatar,
        isChannelVerified: channel.isVerified,
        views: 0,
        createdAt: DateTime.now(),
        likes: 0,
        commentsCount: 0,
        status: 'pending',
      );

      final result = await VideoService().addVideo(newVideo, channel.id!);
      
      if (mounted) {
        setState(() => _isPublishing = false);

        if (result['success'] == true) {
          if (result['status'] == 'pending_verification') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tu canal requiere verificación por tener muchos suscriptores en YouTube.'), backgroundColor: Colors.orange),
            );
            // Navigate to Verification Screen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => VerificationScreen(channelId: channel.id ?? '00000000-0000-0000-0000-000000000000')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video importado con éxito. Metadatos extraídos de YouTube.'), backgroundColor: Colors.green),
            );
            Navigator.pop(context); 
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Error al importar el video.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Importar de YouTube', style: GoogleFonts.outfit(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: AppTheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Solo necesitas el enlace. El sistema extraerá automáticamente el título, descripción y etiquetas de YouTube.',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _urlController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Enlace de YouTube',
                  hintText: 'https://www.youtube.com/watch?v=...',
                  labelStyle: const TextStyle(color: AppTheme.textMuted),
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppTheme.primary),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Requerido';
                  if (!value.contains('youtube.com') && !value.contains('youtu.be')) return 'Debe ser un enlace válido de YouTube';
                  return null;
                },
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isPublishing ? null : _publishVideo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isPublishing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Importar Video',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
