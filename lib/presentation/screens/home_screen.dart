import 'package:flutter/material.dart';
import 'package:pace/presentation/screens/blocks_screen.dart';
import 'package:pace/presentation/screens/focus_screen.dart';
import 'package:pace/presentation/screens/group_screen.dart';
import 'package:pace/presentation/screens/usage_stats_screen.dart';
import 'package:pace/presentation/screens/insights_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // INDEXED SCREENS
  final List<Widget> _screens = [
    const FocusScreen(),
    const GroupScreen(),
    const BlocksScreen(),
    const UsageStatsScreen(),
    const InsightsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    
      body: _screens[_selectedIndex],

      // USING MATERIAL 3 NAVIGATION BAR
      // This matches the 'navigationBarTheme' in your AppTheme file
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent, // 🔥 removes shine
        surfaceTintColor: Colors.transparent, // 🔥 removes overlay tint
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          // Index 0
          NavigationDestination(
            icon: Icon(Icons.center_focus_strong_outlined),
            selectedIcon: Icon(Icons.center_focus_strong),
            label: 'Focus',
          ),
          // Index 1
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Groups',
          ),
          // Index 2
          NavigationDestination(
            icon: Icon(Icons.block_outlined),
            selectedIcon: Icon(Icons.block),
            label: 'Blocks',
          ),
          // Index 3
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Usage',
          ),
          // Index 4
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Insights',
          ),
        ],
      ),
    );
  }
}