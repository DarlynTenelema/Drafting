import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/video_model.dart';
import '../core/services/video_service.dart';
import '../theme/app_theme.dart';

class EditVideoScreen extends StatefulWidget {
  final VideoModel video;
  
  const EditVideoScreen({super.key, required this.video});

  @override
  State<EditVideoScreen> createState() => _EditVideoScreenState();
}

class _EditVideoScreenState extends State<EditVideoScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _tagsController;
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.video.title);
    _descController = TextEditingController(text: widget.video.description);
    _tagsController = TextEditingController(text: widget.video.tags.join(', '));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _saveVideo() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);

    final updatedVideo = VideoModel(
      id: widget.video.id,
      videoId: widget.video.videoId,
      channelId: widget.video.channelId,
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      tags: _tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      channelName: widget.video.channelName,
      channelAvatar: widget.video.channelAvatar,
      isChannelVerified: widget.video.isChannelVerified,
      views: widget.video.views,
      createdAt: widget.video.createdAt,
      likes: widget.video.likes,
      commentsCount: widget.video.commentsCount,
      status: widget.video.status,
    );

    final success = await VideoService().updateVideo(updatedVideo);
    
    setState(() => _isSaving = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video actualizado con éxito'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // Return true to indicate change
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al actualizar el video'), backgroundColor: Colors.red),
        );
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
        title: Text('Editar Video', style: GoogleFonts.outfit(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Título del Video'),
                validator: (value) => value == null || value.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _descController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Descripción'),
                maxLines: 6,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _tagsController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Etiquetas (separadas por comas)'),
                validator: (value) => value == null || value.isEmpty ? 'Añade al menos una etiqueta' : null,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveVideo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Guardar Cambios',
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

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppTheme.textMuted),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppTheme.primary),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
