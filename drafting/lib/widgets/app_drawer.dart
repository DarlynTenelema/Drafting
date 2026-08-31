import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/services/native_service.dart';
import '../core/services/session_service.dart';
import '../core/services/finance_service.dart';
import '../theme/app_theme.dart';
import '../screens/login_screen.dart';
import '../screens/economy_screen.dart';
import '../screens/entrepreneur_onboarding_screen.dart';
import '../screens/creator_dashboard_screen.dart';
import '../screens/help_center_screen.dart';
import '../screens/payment_screen.dart';
import '../screens/consumer_store_screen.dart';
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  GoogleSignInAccount? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUser();
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
    try { await _googleSignIn.disconnect(); } catch (_) {}
    await _googleSignIn.signOut();
    await SessionService.clearSession();
    FinanceService().reset();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
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
            leading: const Icon(Icons.storefront, color: Colors.cyanAccent),
            title: const Text('Tienda de Creadores', style: TextStyle(color: Colors.cyanAccent)),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConsumerStoreScreen(sessionToken: '')));
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
            leading: const Icon(Icons.dashboard_customize, color: Colors.purpleAccent),
            title: const Text('Creator Studio', style: TextStyle(color: Colors.purpleAccent)),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreatorDashboardScreen()));
            },
          ),
          ListTile(
            leading: Image.asset('assets/images/chest_outline.png', width: 36, height: 36),
            title: const Text('Planes de pago', style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final token = await SessionService.getSessionToken();
              if (token != null && mounted) {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaymentScreen(sessionToken: token)));
              }
            },
          ),
          
          ListTile(
            leading: const Icon(Icons.help_outline, color: Colors.white),
            title: const Text('Centro de Ayuda', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen()));
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
    );
  }
}
