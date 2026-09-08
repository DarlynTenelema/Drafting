import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/api_client.dart';
import '../theme/app_theme.dart';
import 'legal_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String sessionToken;
  const SettingsScreen({super.key, required this.sessionToken});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  String _username = '';
  String _profilePic = '';

  final TextEditingController _usernameController = TextEditingController();
  
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
      // Re-trigger the dialog rebuild
      if (mounted) {
        Navigator.pop(context);
        _showEditProfileDialog();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.get('/api/v1/auth/me', authenticated: true);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _username = data['username'] ?? '';
          _profilePic = data['profile_pic'] ?? '';
          _usernameController.text = _username;
        });
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);
    try {
      String finalProfilePic = _profilePic;
      
      if (_selectedImage != null) {
        final file = _selectedImage!;
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_avatar.jpg';
        await Supabase.instance.client.storage.from('avatars').upload(fileName, file);
        finalProfilePic = Supabase.instance.client.storage.from('avatars').getPublicUrl(fileName);
      }

      final response = await ApiClient.put(
        '/api/v1/auth/me',
        authenticated: true,
        body: {
          'username': _usernameController.text.trim(),
          'profile_pic': finalProfilePic,
        },
      );
      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado exitosamente', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
        );
        _fetchProfile();
      } else {
        throw Exception('Error updating profile');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al actualizar perfil', style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Editar Perfil', style: GoogleFonts.outfit(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nombre de usuario',
                    labelStyle: const TextStyle(color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: AppTheme.background,
                      backgroundImage: _selectedImage != null 
                          ? FileImage(_selectedImage!) 
                          : (_profilePic.isNotEmpty ? NetworkImage(_profilePic) : null) as ImageProvider?,
                      child: _selectedImage == null && _profilePic.isEmpty
                          ? const Icon(Icons.camera_alt, size: 40, color: Colors.white54)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Cambiar Foto de Perfil',
                    style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateProfile();
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Ajustes', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Profile Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppTheme.background,
                        backgroundImage: _profilePic.isNotEmpty ? NetworkImage(_profilePic) : null,
                        child: _profilePic.isEmpty ? const Icon(Icons.person, color: Colors.white54, size: 30) : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _username.isNotEmpty ? _username : 'Sin nombre',
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Usuario de Drafting',
                              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: AppTheme.primary),
                        onPressed: _showEditProfileDialog,
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                Text('General', style: GoogleFonts.outfit(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                
                ListTile(
                  leading: const Icon(Icons.share, color: Colors.white),
                  title: const Text('Compartir App', style: TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                  tileColor: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Share.share('¡Únete a Drafting, la mejor app para creadores y coaches de e-sports! https://drafting.gg');
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.privacy_tip, color: Colors.white),
                  title: const Text('Privacidad y Términos', style: TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                  tileColor: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalScreen()));
                  },
                ),
              ],
            ),
    );
  }
}
