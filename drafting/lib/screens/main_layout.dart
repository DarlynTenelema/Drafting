import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'index_screen.dart';
import 'fanarts_screen.dart';
import 'videos_screen.dart';
import 'consumer_store_screen.dart';
import 'chat_coach_screen.dart'; // Import ChatCoachScreen

class MainLayoutScreen extends StatefulWidget {
  final String sessionToken;
  final String? activeGroupName;

  const MainLayoutScreen({
    super.key,
    required this.sessionToken,
    this.activeGroupName,
  });

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _currentIndex = 2; // Default to Home (IndexScreen)

  List<Widget> get _screens => [
        const ChatCoachScreen(), // 0
        const FanartsScreen(), // 1
        IndexScreen(sessionToken: widget.sessionToken, groupName: widget.activeGroupName), // 2
        const VideosScreen(), // 3
        ConsumerStoreScreen(sessionToken: widget.sessionToken), // 4
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      extendBody: true,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.background.withValues(alpha: 0.5),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1)),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: Colors.grey,
          showSelectedLabels: true, // Let's show labels to make it clear which one is the IA
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.smart_toy_outlined, size: 28),
              activeIcon: Icon(Icons.smart_toy, size: 28),
              label: 'IA Coach',
            ),
            BottomNavigationBarItem(
              icon: ImageIcon(AssetImage('assets/images/paintbrush_outline.png'), size: 28),
              activeIcon: ImageIcon(AssetImage('assets/images/paintbrush_solid.png'), size: 28),
              label: 'FanArt',
            ),
            BottomNavigationBarItem(
              icon: ImageIcon(AssetImage('assets/images/home_outline.png'), size: 30),
              activeIcon: ImageIcon(AssetImage('assets/images/home_solid.png'), size: 30),
              label: 'Inicio',
            ),
            BottomNavigationBarItem(
              icon: ImageIcon(AssetImage('assets/images/video_outline.png'), size: 28),
              activeIcon: ImageIcon(AssetImage('assets/images/video_solid.png'), size: 28),
              label: 'Videos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_outlined, size: 28),
              activeIcon: Icon(Icons.storefront, size: 28),
              label: 'Tienda',
            ),
          ],
        ),
      ),
    );
  }
}
