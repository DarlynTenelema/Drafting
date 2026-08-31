import 'dart:async';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/config/app_config.dart';
import '../core/services/native_service.dart';
import '../core/services/session_service.dart';
import '../core/services/finance_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'payment_screen.dart';
import 'info_screen.dart';
import 'economy_screen.dart';
import '../shared/widgets/hextech_orb.dart';
import 'entrepreneur_onboarding_screen.dart';
import 'settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appeal_screen.dart';
import 'dart:convert';
import '../core/services/api_client.dart';
import '../core/state/active_product_state.dart';


class IndexScreen extends StatefulWidget {
  final String? sessionToken;
  final String? groupName; // Optional group name banner
  final Widget? bottomNavBar;
  const IndexScreen({super.key, this.sessionToken, this.groupName, this.bottomNavBar});

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  StreamSubscription? _eventSubscription;
  
  late String _sessionToken;
  bool _isActive = false;
  bool _isPremium = false;
  String _userTier = 'plus';
  int _visibleFields = 1;
  GoogleSignInAccount? _currentUser;
  
  final List<TextEditingController> _otpControllers = List.generate(5, (_) => TextEditingController());

  @override
  void initState() {
    super.initState();
    _sessionToken = widget.sessionToken ?? '';
    _loadSession();
    if (_sessionToken.isNotEmpty) {
      _fetchUserData();
    }
    
    _eventSubscription = NativeService.onEvent.listen((event) {
      if (event['code'] == 402) {
        if (!mounted) return;
        // Payment required
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PaymentScreen(sessionToken: _sessionToken)),
        ).then((result) {
          if (result == true && mounted) {
            _fetchUserData();
          }
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tu suscripción ha expirado. Por favor, renueva tu plan.')),
        );
      } else if (event['code'] == 429) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Has alcanzado el límite de 10 consultas. Debes esperar 60 minutos.')),
        );
      }
    });
    _loadUser();
  }

  void _loadUser() async {
    try {
      final future = GoogleSignIn.instance.attemptLightweightAuthentication();
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

  Future<void> _loadSession() async {
    if (_sessionToken.isNotEmpty) return;
    final token = await SessionService.getSessionToken();
    if (token != null && mounted) {
      setState(() {
        _sessionToken = token;
      });
      // After session token is loaded, fetch user data
      _fetchUserData();
    }
  }

  Future<void> _fetchUserData() async {
    try {
      final response = await ApiClient.get('/api/v1/auth/me');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _isPremium = data['is_premium'] == true;
            _userTier = data['plan_tier'] ?? 'plus';
            if (_userTier == 'pro') _visibleFields = 2;
            if (_userTier == 'ultra') _visibleFields = 1; // Start with 1, can add up to 5
          });
        }
        if (data['is_pending_ban'] == true) {
          if (!mounted) return;
          // Force navigate to AppealScreen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => AppealScreen(sessionToken: _sessionToken)),
          );
        }
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
  }

  Future<void> _handleLogout() async {
    await NativeService.stopCaptureService();
    try { await GoogleSignIn.instance.disconnect(); } catch (_) {}
    await GoogleSignIn.instance.signOut();
    await SessionService.clearSession();
    FinanceService().reset();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<bool> _checkAndShowDisclosure() async {
    final prefs = await SharedPreferences.getInstance();
    final hasAccepted = prefs.getBool('hasAcceptedDisclosure') ?? false;
    
    if (hasAccepted) {
      return true;
    }

    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text(
            'Permiso de Captura de Pantalla',
            style: TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Drafting requiere capturar tu pantalla para analizar la partida. '
            'Las imágenes se enviarán a nuestros servidores en la nube para procesar la recomendación con Inteligencia Artificial. '
            'No almacenamos tus imágenes permanentemente ni compartimos datos con terceros.\n\n'
            '¿Aceptas el uso de la captura de pantalla para esta funcionalidad?',
            style: TextStyle(color: AppTheme.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Rechazar', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Acepto', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await prefs.setBool('hasAcceptedDisclosure', true);
      return true;
    }
    return false;
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

      final hasPermission = await _checkAndShowDisclosure();
      if (!hasPermission) {
        return;
      }

      String otpString = _otpControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).join(', ');

      String? activeCreatorId = ActiveProductState().activeCreatorIdNotifier.value;

      bool started = await NativeService.startCaptureService(
        baseUrl: AppConfig.apiBaseUrl,
        sessionToken: _sessionToken,
        mainRole: "Auto",
        secondaryRole: "Auto",
        autofillRole: "Auto",
        isPremium: _isPremium,
        planTier: _userTier,
        otpChampions: otpString,
        activeCreatorId: activeCreatorId,
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

  // Removed _buildTextField

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: widget.bottomNavBar,
      drawer: Drawer(
        backgroundColor: AppTheme.surface,
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppTheme.background),
              child: Center(
                child: Text(
                  'Drafting',
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ListTile(
              leading: Image.asset('assets/images/scroll_outline.png', width: 36, height: 36),
              title: const Text('Emprender', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EntrepreneurOnboardingScreen()));
              },
            ),
            ListTile(
              leading: Image.asset('assets/images/crystal_coin_outline.png', width: 36, height: 36),
              title: const Text('Compra de monedas', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EconomyScreen()));
              },
            ),
            ListTile(
              leading: Image.asset('assets/images/chest_outline.png', width: 36, height: 36),
              title: const Text('Planes de pago', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaymentScreen(sessionToken: _sessionToken)));
                if (result == true && mounted) {
                  _fetchUserData();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.white),
              title: const Text('Ajustes / Configuración', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(sessionToken: _sessionToken)));
              },
            ),
            const Spacer(),
            const Divider(color: Colors.white24),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.background,
                backgroundImage: _currentUser?.photoUrl != null ? NetworkImage(_currentUser!.photoUrl!) : null,
                radius: 16,
                child: _currentUser?.photoUrl == null ? const Icon(Icons.person, color: AppTheme.textMuted, size: 20) : null,
              ),
              title: Text(_currentUser?.displayName ?? 'Jugador', style: const TextStyle(color: Colors.white, fontSize: 14)),
              trailing: IconButton(
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                onPressed: _handleLogout,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
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
                    Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu, color: AppTheme.textMuted),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                      ),
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
                      icon: const Icon(Icons.info_outline, color: AppTheme.textMuted),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const InfoScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Column(
                    children: [
                      // Active Product Banner
                      ValueListenableBuilder<String?>(
                        valueListenable: ActiveProductState().activeProductNotifier,
                        builder: (context, activeProduct, child) {
                          if (activeProduct == null) return const SizedBox.shrink();
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 24.0),
                            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5), width: 1),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.star, color: Colors.greenAccent, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '✨ Sistema Activo: $activeProduct',
                                        style: const TextStyle(
                                          color: Colors.greenAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      // Desactivar lógica
                                      await ActiveProductState().clearActiveProduct();
                                      if (_isActive) {
                                        _toggleService(); // Stop the service if running
                                      }
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Sistema de tienda desactivado. Usa el modo por defecto.')),
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                                      foregroundColor: Colors.redAccent,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                                      ),
                                    ),
                                    icon: const Icon(Icons.power_settings_new, size: 18),
                                    label: const Text('Desactivar Sistema', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      if (_isPremium && (_userTier == 'pro' || _userTier == 'ultra')) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Tus Campeones y Roles (IA)',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textLight,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Especifica parámetros exactos para la IA. Pro: 2 campos. Ultra: Hasta 5 campos.',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ...List.generate(_visibleFields, (index) {
                          List<String> labels = ['Otp', 'Main 1', 'Main 2', 'Linea main 1', 'Linea main 2'];
                          if (_userTier == 'pro') labels = ['Otp', 'Main'];
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: TextField(
                              controller: _otpControllers[index],
                              style: const TextStyle(color: AppTheme.textLight),
                              decoration: InputDecoration(
                                labelText: index < labels.length ? labels[index] : 'Extra',
                                labelStyle: const TextStyle(color: AppTheme.textMuted),
                                filled: true,
                                fillColor: AppTheme.background,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.white12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.white12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: AppTheme.primary),
                                ),
                              ),
                            ),
                          );
                        }),
                        if (_userTier == 'ultra' && _visibleFields < 5)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _visibleFields++;
                              });
                            },
                            icon: const Icon(Icons.add, color: AppTheme.primary),
                            label: const Text('Añadir campo', style: TextStyle(color: AppTheme.primary)),
                          ),
                      ],

                      const SizedBox(height: 40),
                      
                      // Central Action Button with Glow (Hextech Orb)
                      HextechOrb(
                        isActive: _isActive,
                        onTap: _toggleService,
                      ),
                    ],
                  ),
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
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
