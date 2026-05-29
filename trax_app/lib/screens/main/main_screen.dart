import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import '../session/session_screen.dart';
import '../trails/trails_screen.dart';
import '../ride/ride_screen.dart';
import '../garage/garage_screen.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // Keys to invoke each tab page's public `refresh()` whenever the user
  // taps that tab in the bottom nav. Pages stay alive in the IndexedStack,
  // so without this they'd only ever load once per app launch.
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<SessionScreenState> _sessionKey = GlobalKey<SessionScreenState>();
  final GlobalKey<TrailsScreenState> _trailsKey = GlobalKey<TrailsScreenState>();
  final GlobalKey<GarageScreenState> _garageKey = GlobalKey<GarageScreenState>();

  late final List<Widget> _pages = [
    HomeScreen(key: _homeKey, onSwitchTab: _switchTab),
    TrailsScreen(key: _trailsKey),
    const SizedBox(),
    SessionScreen(key: _sessionKey),
    GarageScreen(key: _garageKey),
  ];

  /// Public-style helper for child pages (e.g. HomeScreen "See all")
  /// that need to jump to a sibling tab in the bottom nav.
  void _switchTab(int index) => _onTabTapped(index);

  void _onTabTapped(int index) {
    if (index == 2) return;
    setState(() => _currentIndex = index);
    // Trigger a fresh load every time the user enters a tab.
    switch (index) {
      case 0:
        _homeKey.currentState?.refresh();
        break;
      case 1:
        _trailsKey.currentState?.refresh();
        break;
      case 3:
        _sessionKey.currentState?.refresh();
        break;
      case 4:
        _garageKey.currentState?.refresh();
        break;
    }
  }

  void _openRideScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RideScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '100', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: AppColors.surface,
        elevation: 8,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_outlined, Icons.home, 'Home', 0),
              _buildNavItem(Icons.map_outlined, Icons.map, 'Map', 1),
              const SizedBox(width: 48),
              _buildNavItem(Icons.timeline_outlined, Icons.timeline, 'Session', 3),
              _buildNavItem(Icons.garage_outlined, Icons.garage, 'Garage', 4),
            ],
          ),
        ),
      ),
      floatingActionButton: SizedBox(
        width: 60,
        height: 60,
        child: FloatingActionButton(
          onPressed: _openRideScreen,
          tooltip: 'Ride',
          backgroundColor: AppColors.primary,
          elevation: 4,
          shape: const CircleBorder(),
          // Dynamic dirt-bike vibe: tilt the two-wheeler icon slightly
          // backward to suggest a wheelie / acceleration pose.
          child: Transform.rotate(
            angle: -0.30, // ~ -17°
            child: const Icon(
              Icons.two_wheeler,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildNavItem(IconData icon, IconData activeIcon, String label, int index) {
    final isActive = _currentIndex == index;
    return InkWell(
      onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon, color: isActive ? AppColors.primary : AppColors.textSecondary, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: isActive ? AppColors.primary : AppColors.textSecondary, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
