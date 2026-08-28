import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';
import '../core/services/fanart_service.dart';

class UploadFanartScreen extends StatefulWidget {
  const UploadFanartScreen({super.key});

  @override
  State<UploadFanartScreen> createState() => _UploadFanartScreenState();
}

class _UploadFanartScreenState extends State<UploadFanartScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  XFile? _selectedImage;
  
  final List<String> _availableTags = [
    'Acción', 'Romance', 'Terror', 'Live action', 'Sexy', 'Fantasía', 
    'Sci-Fi', 'Cyberpunk', 'Steampunk', 'Mecha', 'Furry', 'Chibi', 
    'Realista', 'Minimalista', 'Pixel Art', 'Anime', 'Cómic', 'Concept Art', 
    'Sketch', '3D', 'Retrato', 'Wallpaper', 'Vertical', 'Icon', 'Ahri', 
    'Jinx', 'Mid', 'ADC', 'Dark', 'Cute', 'Epic', 'Classic', 'Arcane', 
    'Fighter', 'Assassin', 'Mage', 'Support', 'Tank', 'Square', 'Horizontal', 'Banner'
  ];
  final List<String> _selectedTags = [];

  bool _isUploading = false;

  void _handleUpload() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona una imagen primero.')),
      );
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa un nombre para la imagen.')),
      );
      return;
    }

    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa un precio válido en GoldenCoins.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    final result = await FanartService().uploadFanart(
      _nameController.text.trim(),
      price,
      _selectedImage!.path,
      tags: _selectedTags.join(','),
    );

    if (!mounted) return;

    setState(() {
      _isUploading = false;
    });

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fanart subido correctamente.')),
      );
      Navigator.pop(context, true); // Go back and indicate success
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = pickedFile;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Subir Fanart',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    style: BorderStyle.solid,
                  ),
                  image: _selectedImage != null
                      ? DecorationImage(
                          image: FileImage(File(_selectedImage!.path)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _selectedImage == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 64, color: AppTheme.textMuted),
                          const SizedBox(height: 16),
                          Text(
                            'Toca para seleccionar imagen',
                            style: GoogleFonts.inter(color: AppTheme.textMuted),
                          ),
                        ],
                      )
                    : Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              iconSize: 20,
                              onPressed: () => setState(() => _selectedImage = null),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // Name Input
            Text(
              'Nombre de la imagen',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Ej. Spirit Blossom Ahri',
              ),
            ),
            const SizedBox(height: 24),
            
            // Price Input
            Text(
              'Precio (GoldenCoins)',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Ej. 15',
                prefixIcon: Icon(Icons.monetization_on, color: Color(0xFFFFD700)),
              ),
            ),
            const SizedBox(height: 24),

            // Tags
            Text(
              'Etiquetas',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Selecciona las que mejor describan tu imagen para ayudar a que sea encontrada.',
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
                        _selectedTags.add(tag);
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

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _handleUpload,
                child: _isUploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Subir Imagen',
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
