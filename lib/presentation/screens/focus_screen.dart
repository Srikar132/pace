import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pace/core/constants/images.dart';
import 'package:pace/core/router/app_router.dart' show profileRoute , activeSessionRoute;
import 'package:pace/models/focus_time_bottom_model.dart';
import 'package:pace/models/model_manager.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/focus_session_provider.dart';
import 'package:pace/presentation/providers/blocked_content_provider.dart';
import 'package:pace/presentation/providers/settings_provider.dart';
import 'package:pace/presentation/providers/background_image_provider.dart';
import 'package:pace/presentation/providers/usage_stats_provider.dart';
import 'package:pace/widgets/focus_timer_widget.dart';
import 'package:pace/widgets/lumo_mascot_widget.dart';
import 'package:pace/widgets/background_image_selector.dart';
import 'dart:math';

class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  // List of motivational quotes
  final List<String> _quotes = [
    "Stay committed to your decisions, but stay flexible in your approach.",
    "Concentrate all your thoughts upon the work in hand.",
    "The successful warrior is the average man, with laser-like focus.",
    "Lack of direction, not lack of time, is the problem.",
    "Focus on being productive instead of busy.",
    "The ability to focus is the key skill of the 21st century.",
    "Success demands singleness of purpose.",
  ];

  int _currentQuoteIndex = -1;
  final Random _random = Random();

  // Function to change quotes when Lumo is tapped
  void _changeQuote() {
    setState(() {
      int newIndex;
      do {
        newIndex = _random.nextInt(_quotes.length);
      } while (newIndex == _currentQuoteIndex && _quotes.length > 1);
      _currentQuoteIndex = newIndex;
    });
  }

  // Show focus mode modal and handle session creation
  void _showFocusModeModal() {
    BottomSheetManager.show(
      context: context,
      child: FocusTimeBottomSheet(
        onSave: () async {
          // Start focus session and navigate to active screen
          await _startFocusSession();
        },
      ),
    );
  }

  // Show background image selector modal
  void _showBackgroundSelector() {
    BottomSheetManager.show(
      context: context,
      height: MediaQuery.of(context).size.height * 0.8,
      child: const BackgroundImageSelector(),
    );
  }

  // Start focus session with current settings
  Future<void> _startFocusSession() async {
    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) return;

      final settingsAsync = ref.read(userSettingsProvider(user.uid));
      final settings = settingsAsync.value;

      if (settings == null) return;

      // Get blocked content from the proper blocked content provider
      final blockedContentAsync = ref.read(blockedContentProvider(user.uid));
      final blockedContent = blockedContentAsync.value;

      // Get permanently blocked apps from blocked content provider
      final allBlockedApps = blockedContent?.permanentlyBlockedApps ?? [];

      // Get blocked websites from blocked content provider
      final blockedWebsites =
          blockedContent?.blockedWebsites
              .where((w) => w.isActive)
              .map(
                (w) => {'url': w.url, 'name': w.name, 'isActive': w.isActive},
              )
              .toList() ??
          [];

      // Get short form blocks
      final shortFormBlocks = blockedContent?.shortFormBlocks ?? {};
      final shortFormBlocked = shortFormBlocks.values.any(
        (block) => block.isBlocked,
      );

      // Start the focus session using the provider
      await ref
          .read(focusSessionProvider.notifier)
          .startSession(
            plannedDuration: settings.defaultDuration,
            sessionType: settings.timerMode,
            blockedApps: allBlockedApps,
            blockedWebsites: blockedWebsites,
            shortFormBlocked: shortFormBlocked,
            notificationsBlocked: true, // Default to blocking notifications
          );

      // Navigate to active focus screen. startSession() above already
      // populated focusSessionProvider's state, which ActiveFocusScreen
      // reads directly - no need to pass session data through the route.
      if (mounted) {
        context.push(activeSessionRoute);
      }
    } catch (e) {
      debugPrint('Error starting focus session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start focus session: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      data: (user) {
        if (user == null) {
          return const Center(child: Text('Please login first'));
        }

        return Stack(
          children: [
            // 1. Background Image Layer - Now using dynamic background
            Positioned.fill(
              child: Consumer(
                builder: (context, ref, child) {
                  final currentBackground = ref.watch(
                    currentBackgroundImageProvider,
                  );
                  return Image.asset(
                    currentBackground,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to default if image fails to load
                      return Image.asset(
                        kHomeBackgroundImage,
                        fit: BoxFit.cover,
                      );
                    },
                  );
                },
              ),
            ),

            // 2. Transparent InkWell & Column Layer
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {},
                  onLongPress: _showBackgroundSelector,
                  splashColor: Colors.white.withAlpha(30),
                  highlightColor: Colors.white.withAlpha(10),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Custom Header
                          _buildHeader(context, user),

                          const SizedBox(height: 100),

                          // Focus Timer Widget - now handles its own settings
                          FocusTimerWidget(onTap: _showFocusModeModal),

                          const Spacer(),

                          // Quotation Card
                          if (_currentQuoteIndex > -1) _buildQuoteCard(),

                          const SizedBox(height: 10),

                          // Lumo Mascot - Tap to change quote
                          LumoMascotWidget(onTap: _changeQuote),

                          const SizedBox(height: 50),

                          // Start Focus Mode Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _showFocusModeModal,
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(100),
                                ),
                              ),
                              child: const Text('Start focus mode'),
                            ),
                          ),

                          const SizedBox(height: 5),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) =>
          const Scaffold(body: Center(child: Text('Error loading user data'))),
    );
  }

  // Quotation Card Widget
  Widget _buildQuoteCard() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey<int>(_currentQuoteIndex),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withAlpha(60),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.format_quote,
              color: Colors.white.withValues(alpha: 0.6),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _quotes[_currentQuoteIndex],
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.format_quote,
              color: Colors.white.withValues(alpha: 0.6),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, user) {
    return Row(
      children: [
        // User Profile Avatar
        GestureDetector(
          onTap: () => context.push(profileRoute),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              backgroundImage: user.photoURL != null
                  ? NetworkImage(user.photoURL!)
                  : null,
              child: user.photoURL == null
                  ? Text(
                      user.firstName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          ),
        ),

        const Spacer(),

        // Usage Time Card - Using today's usage stats (excluding pace app)
        Consumer(
          builder: (context, ref, child) {
            final todayUsageAsync = ref.watch(todayUsageStatsProvider);

            return todayUsageAsync.when(
              data: (usageStats) {
                return _buildStatCard(
                  label: 'Usage',
                  value: usageStats.formattedTotalTimeExcludingSelf,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                );
              },
              loading: () => _buildStatCard(
                label: 'Usage',
                value: '...',
                backgroundColor: Colors.white.withValues(alpha: 0.15),
              ),
              error: (_, _) => _buildStatCard(
                label: 'Usage',
                value: '0m',
                backgroundColor: Colors.white.withValues(alpha: 0.15),
              ),
            );
          },
        ),

        const Spacer(),

        // Streak/Action Icon
        GestureDetector(
          onTap: () {
            // Open settings, notifications, or streak details
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).focusColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.local_fire_department,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(height: 1),
                Text(
                  '${user.currentStreak}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
