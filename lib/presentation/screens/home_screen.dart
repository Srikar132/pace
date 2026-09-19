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

  // Lazily built so tabs the user never opens don't pay init/network cost.
  // Once built, kept alive by IndexedStack (index null -> not built yet).
  static const _screenBuilders = <WidgetBuilder>[
    _buildFocus,
    _buildGroup,
    _buildBlocks,
    _buildUsage,
    _buildInsights,
  ];
  final List<Widget?> _screens = List.filled(_screenBuilders.length, null);

  static Widget _buildFocus(BuildContext _) => const FocusScreen();
  static Widget _buildGroup(BuildContext _) => const GroupScreen();
  static Widget _buildBlocks(BuildContext _) => const BlocksScreen();
  static Widget _buildUsage(BuildContext _) => const UsageStatsScreen();
  static Widget _buildInsights(BuildContext _) => const InsightsScreen();

  @override
  Widget build(BuildContext context) {
    _screens[_selectedIndex] ??= _screenBuilders[_selectedIndex](context);

    return Scaffold(
      // Keyboard viewInsets are a single global window value - every
      // Scaffold in the tree reacts to them by default, not just the one
      // actually hosting the focused field. Modal sheets opened above this
      // (FocusTimeBottomSheet, BlockAppsSheet) already handle their own
      // keyboard inset manually, so this base Scaffold reacting too was
      // redundant - it made the tab behind the sheet visibly shift/resize
      // whenever a text field inside the sheet got focus. Tabs that do need
      // resize-avoidance for their own inline fields (UsageStatsScreen) have
      // their own nested Scaffold, so they're unaffected by this.
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var i = 0; i < _screens.length; i++)
            _screens[i] ?? const SizedBox.shrink(),
        ],
      ),

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