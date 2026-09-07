import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../core/services/creator_service.dart';
import '../core/services/api_client.dart';
import 'upload_fanart_screen.dart';

class CreatorSetupScreen extends StatefulWidget {
  final bool isForVideo;
  const CreatorSetupScreen({super.key, this.isForVideo = false});

  @override
  State<CreatorSetupScreen> createState() => _CreatorSetupScreenState();
}

class _CreatorSetupScreenState extends State<CreatorSetupScreen> {
  final TextEditingController _artistNameController = TextEditingController();
  
  final List<String> _availableTags = [
    'Acción', 'Romance', 'Terror', 'Live action', 'Sexy', 'Fantasía', 
    'Sci-Fi', 'Cyberpunk', 'Steampunk', 'Mecha', 'Furry', 'Chibi', 
    'Realista', 'Minimalista', 'Pixel Art', 'Anime', 'Cómic', 'Concept Art', 
    'Sketch', '3D', 'Retrato', 'Wallpaper', 'Vertical', 'Icon', 'Ahri', 
    'Jinx', 'Mid', 'ADC', 'Dark', 'Cute', 'Epic', 'Classic', 'Arcane', 
    'Fighter', 'Assassin', 'Mage', 'Support', 'Tank', 'Square', 'Horizontal', 'Banner'
  ];
  final List<String> _selectedTags = [];
  bool _isLoading = false;

  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  void _handleCreateProfile() async {
    final artistName = _artistNameController.text.trim();
    if (artistName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa tu nombre de artista.')),
      );
      return;
    }

    if (_selectedTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona al menos una etiqueta.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? profilePicUrl;
      if (_selectedImage != null) {
        final file = _selectedImage!;
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_avatar.jpg';
        await Supabase.instance.client.storage.from('avatars').upload(fileName, file);
        profilePicUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(fileName);
      }

      // 1. Update Global Profile (Username and Pic)
      await ApiClient.put(
        '/api/v1/auth/me',
        authenticated: true,
        body: {
          'username': artistName,
          if (profilePicUrl != null) 'profile_pic': profilePicUrl,
        },
      );

      // 2. Create Creator Profile
      final result = await CreatorService().createCreatorProfile(artistName, _selectedTags);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      if (result['success']) {
        if (widget.isForVideo) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const UploadFanartScreen()),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Error desconocido'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _artistNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Espacio de Creador',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¡Bienvenido futuro creador!',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Antes de subir tu primera obra, configura tu perfil público.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 32),

            // Profile Picture
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
                'Toca para subir tu Foto de Perfil',
                style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
              ),
            ),
            const SizedBox(height: 32),

            // Artist Name
            Text(
              'Nombre de Usuario (Artista)',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _artistNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Ej. DaVinci_LoL',
              ),
            ),
            const SizedBox(height: 32),

            // Tags
            Text(
              'Temáticas principales',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Selecciona hasta 5 etiquetas que mejor describan tu estilo o público objetivo.',
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableTags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return ChoiceChip(
                  label: Text(tag),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (_selectedTags.length < 5) {
                          _selectedTags.add(tag);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Puedes seleccionar un máximo de 5 etiquetas.')),
                          );
                        }
                      } else {
                        _selectedTags.remove(tag);
                      }
                    });
                  },
                  backgroundColor: AppTheme.surface,
                  selectedColor: AppTheme.primary,
                  labelStyle: GoogleFonts.inter(
                    color: isSelected ? Colors.white : AppTheme.textMuted,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 40),

            // Create Space Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleCreateProfile,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Crear Espacio',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
