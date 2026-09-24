import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'index_screen.dart';
import 'index_screen.dart';
import 'chat_coach_screen.dart'; // Import ChatCoachScreen
import 'trivia_screen.dart';

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
  int _currentIndex = 1; // Default to Home (IndexScreen)

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1)),
      ),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
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
            icon: ImageIcon(AssetImage('assets/images/home_outline.png'), size: 30),
            activeIcon: ImageIcon(AssetImage('assets/images/home_solid.png'), size: 30),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.quiz_outlined, size: 28),
            activeIcon: Icon(Icons.quiz, size: 28),
            label: 'Trivia',
          ),
        ],
      ),
    );
  }

  List<Widget> get _screens => [
        ChatCoachScreen(bottomNavBar: _buildBottomNavBar()), // 0
        IndexScreen(sessionToken: widget.sessionToken, groupName: widget.activeGroupName, bottomNavBar: _buildBottomNavBar()), // 1
        TriviaScreen(bottomNavBar: _buildBottomNavBar()), // 2
      ];

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _currentIndex,
      children: _screens,
    );
  }
}
