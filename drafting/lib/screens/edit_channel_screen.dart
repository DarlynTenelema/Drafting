import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/video_model.dart';
import '../core/services/video_service.dart';
import '../theme/app_theme.dart';

class EditChannelScreen extends StatefulWidget {
  const EditChannelScreen({super.key});

  @override
  State<EditChannelScreen> createState() => _EditChannelScreenState();
}

class _EditChannelScreenState extends State<EditChannelScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _avatarController;
  late TextEditingController _bannerController;
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final channel = VideoService().currentUserChannel;
    _nameController = TextEditingController(text: channel?.channelName ?? '');
    _descController = TextEditingController(text: channel?.description ?? '');
    _avatarController = TextEditingController(text: channel?.channelAvatar ?? '');
    _bannerController = TextEditingController(text: channel?.bannerUrl ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _avatarController.dispose();
    _bannerController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);

    final updatedChannel = ChannelModel(
      channelName: _nameController.text.trim(),
      channelAvatar: _avatarController.text.trim(),
      description: _descController.text.trim(),
      bannerUrl: _bannerController.text.trim(),
    );

    final success = await VideoService().updateChannel(updatedChannel);
    
    setState(() => _isSaving = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado con éxito'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al actualizar el perfil'), backgroundColor: Colors.red),
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
        title: Text('Editar Perfil', style: GoogleFonts.outfit(color: Colors.white)),
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
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Nombre del Canal'),
                validator: (value) => value == null || value.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _descController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Descripción / Biografía'),
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _avatarController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('URL Foto de Perfil'),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _bannerController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('URL Banner (Cabecera)'),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
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
