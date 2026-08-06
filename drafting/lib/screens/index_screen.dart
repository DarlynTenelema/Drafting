import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/config/app_config.dart';
import '../core/services/native_service.dart';
import '../core/services/session_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'payment_screen.dart';

class IndexScreen extends StatefulWidget {
  final String? sessionToken;
  const IndexScreen({super.key, this.sessionToken});

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  final TextEditingController mainRoleController = TextEditingController();
  final TextEditingController secondaryRoleController = TextEditingController();
  final TextEditingController autofillRoleController = TextEditingController();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  GoogleSignInAccount? _currentUser;
  
  late String _sessionToken;
  bool _isActive = false;
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _sessionToken = widget.sessionToken ?? '';
    _loadSession();
    _loadUser();
    
    _eventSubscription = NativeService.onEvent.listen((event) {
      if (event['code'] == 402) {
        if (!mounted) return;
        // Payment required
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PaymentScreen(sessionToken: _sessionToken)),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tu suscripción ha expirado. Por favor, renueva tu plan.')),
        );
      } else if (event['code'] == 429) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes esperar 20 minutos entre consultas.')),
        );
      }
    });
  }

  Future<void> _loadSession() async {
    if (_sessionToken.isNotEmpty) return;
    final token = await SessionService.getSessionToken();
    if (token != null && mounted) {
      setState(() {
        _sessionToken = token;
      });
    }
  }

  void _loadUser() async {
    try {
      final future = _googleSignIn.attemptLightweightAuthentication();
      if (future != null) {
        final account = await future;
        if (mounted) {
          setState(() {
            _currentUser = account;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    }
  }

  Future<void> _handleLogout() async {
    await NativeService.stopCaptureService();
    await _googleSignIn.signOut();
    await SessionService.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _toggleService() async {
    if (_isActive) {
      await NativeService.stopCaptureService();
      if (!mounted) return;
      setState(() { _isActive = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servicio detenido')),
      );
    } else {
      if (_sessionToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sesión no válida. Inicia sesión de nuevo.')),
        );
        return;
      }

      bool started = await NativeService.startCaptureService(
        baseUrl: AppConfig.apiBaseUrl,
        sessionToken: _sessionToken,
        mainRole: mainRoleController.text.isEmpty ? "Top" : mainRoleController.text,
        secondaryRole: secondaryRoleController.text.isEmpty ? "Mid" : secondaryRoleController.text,
        autofillRole: autofillRoleController.text.isEmpty ? "Support" : autofillRoleController.text,
      );

      if (started) {
        if (!mounted) return;
        setState(() { _isActive = true; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Servicio activado en segundo plano'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    }
  }

  Widget _buildTextField(String label, String hint, IconData icon, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: AppTheme.textLight),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppTheme.primary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.background,
              AppTheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: AppTheme.textMuted),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ayuda e información')),
                        );
                      },
                    ),
                    Text(
                      'Drafting',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textLight,
                        letterSpacing: 1.5,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: AppTheme.textMuted),
                      onPressed: _handleLogout,
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Column(
                    children: [
                      // Text Fields
                      _buildTextField(
                        'Línea Main',
                        'Ej: Mid Lane',
                        Icons.star_border_outlined,
                        mainRoleController,
                      ),
                      _buildTextField(
                        'Segunda Línea',
                        'Ej: Jungla',
                        Icons.swap_calls,
                        secondaryRoleController,
                      ),
                      _buildTextField(
                        'Rol Autofill',
                        'Ej: Support',
                        Icons.shield_outlined,
                        autofillRoleController,
                      ),
                      
                      const SizedBox(height: 60),
                      
                      // Central Action Button with Glow
                      GestureDetector(
                        onTap: _toggleService,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isActive ? Colors.redAccent : AppTheme.primary,
                            boxShadow: [
                              BoxShadow(
                                color: (_isActive ? Colors.redAccent : AppTheme.primary).withValues(alpha: 0.5),
                                blurRadius: 40,
                                spreadRadius: 10,
                                offset: const Offset(0, 0),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _isActive ? 'DETENER' : 'ACTIVAR',
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      
                    ],
                  ),
                ),
              ),
              
              // Bottom Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // User Profile
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppTheme.surface,
                          backgroundImage: _currentUser?.photoUrl != null
                              ? NetworkImage(_currentUser!.photoUrl!)
                              : null,
                          child: _currentUser?.photoUrl == null
                              ? const Icon(Icons.person, color: AppTheme.textMuted)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _currentUser?.displayName ?? 'Jugador',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: AppTheme.textLight,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    
                    // Settings / Subscription
                    IconButton(
                      icon: const Icon(Icons.stars, color: AppTheme.primary),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PaymentScreen(sessionToken: _sessionToken),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    mainRoleController.dispose();
    secondaryRoleController.dispose();
    autofillRoleController.dispose();
    super.dispose();
  }
}
