import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../core/services/video_service.dart';
import '../theme/app_theme.dart';
import 'upload_video_screen.dart';

class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _createChannel() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isCreating = true);

      final name = _nameController.text;
      
      final avatarUrl = _selectedImage != null 
          ? _selectedImage!.path 
          : 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=random';
      
      final success = await VideoService().createChannel(name, avatarUrl);
      
      if (mounted) {
        setState(() => _isCreating = false);

        if (success) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const UploadVideoScreen()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al crear el canal en el servidor'), backgroundColor: Colors.red),
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
        title: Text('Crear Canal', style: GoogleFonts.outfit(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Únete como Creador',
                style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea tu canal para empezar a compartir videos y guías con la comunidad.',
                style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 32),
              
              // Avatar Picker
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: AppTheme.surface,
                    backgroundImage: _selectedImage != null ? FileImage(_selectedImage!) : null,
                    child: _selectedImage == null
                        ? const Icon(Icons.camera_alt, size: 40, color: Colors.white54)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Toca para subir un Logo/Avatar',
                  style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                ),
              ),
              const SizedBox(height: 32),

              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nombre del Canal',
                  labelStyle: const TextStyle(color: AppTheme.textMuted),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppTheme.primary),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Requerido' : null,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreating ? null : _createChannel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isCreating
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          'Crear Canal y Continuar',
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
