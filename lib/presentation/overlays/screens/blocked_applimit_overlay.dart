import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/overlay_provider.dart';
import '../widgets/overlay_background.dart';

class AppLimitOverlay extends ConsumerStatefulWidget {
  const AppLimitOverlay({super.key});

  @override
  ConsumerState<AppLimitOverlay> createState() => _AppLimitOverlayState();
}

class _AppLimitOverlayState extends ConsumerState<AppLimitOverlay>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100), // Faster
      vsync: this,
    );

    // Start animations immediately - no slide
    _scaleController.forward();
    Future.delayed(const Duration(milliseconds: 100), () {
      _progressController.forward();
    });

    // Vibrate to indicate limit reached
    Future.microtask(() {
      ref.read(overlayDataProvider.notifier).vibrate('triple');
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlayState = ref.watch(overlayDataProvider);
    final overlayNotifier = ref.read(overlayDataProvider.notifier);

    if (overlayState.isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final appName =
        overlayState.overlayData['appName'] as String? ?? 'Unknown App';
    final usedMinutes = overlayState.overlayData['usedMinutes'] as int? ?? 0;
    final limitMinutes = overlayState.overlayData['limitMinutes'] as int? ?? 60;
    final limitType =
        overlayState.overlayData['limitType'] as String? ?? 'daily';
    final allowOverride =
        overlayState.overlayData['allowOverride'] as bool? ?? false;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: OverlayBackground(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Usage progress ring
                  /*ScaleTransition(
                      scale: CurvedAnimation(
                        parent: _scaleController,
                        curve:  Curves.elasticOut,
                      ),
                      child: UsageProgressRing(
                        progress: usagePercentage / 100.0,
                        usedMinutes: usedMinutes,
                        limitMinutes:  limitMinutes,
                        animationController: _progressController,
                      ),
                    ),*/
                  const SizedBox(height: 32),

                  // Limit exceeded message
                  FadeTransition(
                    opacity: _scaleController,
                    child: _buildLimitMessage(appName, limitType),
                  ),

                  const SizedBox(height: 24),

                  // Limit info card
                  /*SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _slideController,
                        curve: Curves.easeOut,
                      )),
                      child: LimitInfoCard(
                        appName: appName,
                        usedMinutes: usedMinutes,
                        limitMinutes:  limitMinutes,
                        limitType:  limitType,
                        timeUntilReset: timeUntilReset,
                      ),
                    ),*/
                  const SizedBox(height: 32),

                  // Override options (if allowed)
                  /*if (allowOverride)
                      FadeTransition(
                        opacity: _scaleController,
                        child: OverrideOptions(
                          onOverride: (duration) => _handleOverride(
                            context,
                            overlayNotifier,
                            overlayState.overlayData['packageName'] as String? ?? '',
                            duration,
                          ),
                        ),
                      ),*/
                  const SizedBox(height: 24),

                  // Action buttons
                  FadeTransition(
                    opacity: _scaleController,
                    child: _buildActionButtons(overlayNotifier, allowOverride),
                  ),

                  const SizedBox(height: 16),

                  // Usage insights
                  _buildUsageInsights(usedMinutes, limitMinutes),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLimitMessage(String appName, String limitType) {
    return Column(
      children: [
        Text(
          '${limitType.capitalize()} Limit Exceeded',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
          ),
          child: Text(
            appName,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(OverlayDataNotifier notifier, bool allowOverride) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => notifier.goHome(),
                icon: const Icon(Icons.home),
                label: const Text('Go Home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withValues(alpha: 0.2),
                  foregroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Colors.green.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            if (!allowOverride) ...[
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showAlternativeApps(context),
                  icon: const Icon(Icons.apps),
                  label: const Text('Alternatives'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.withValues(alpha: 0.2),
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.blue.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (!allowOverride) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showUsageStats(context),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('View Usage Stats'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: BorderSide(color: Colors.orange.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUsageInsights(int usedMinutes, int limitMinutes) {
    final hoursUsed = (usedMinutes / 60).toStringAsFixed(1);
    final percentageUsed = ((usedMinutes / limitMinutes) * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(
            'Usage Insight',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ve used this app for $hoursUsed hours today ($percentageUsed% over your limit). Consider taking a break and engaging in other activities.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Future<void> _handleOverride(
  //   BuildContext context,
  //   OverlayDataNotifier notifier,
  //   String packageName,
  //   int minutes,
  // ) async {
  //   final success = await notifier.overrideAppLimit(
  //     packageName: packageName,
  //     overrideDurationMinutes: minutes,
  //   );

  //   if (success && context.mounted) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Limit overridden for $minutes minutes'),
  //         backgroundColor: Colors.orange,
  //         behavior: SnackBarBehavior.floating,
  //       ),
  //     );

  //     // Close overlay after short delay
  //     Future.delayed(const Duration(seconds: 1), () {
  //       notifier.closeOverlay();
  //     });
  //   }
  // }

  void _showAlternativeApps(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Try These Instead',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildAlternativeItem(
              'Books & Reading',
              'Kindle, Audible, or physical books',
              Icons.menu_book,
            ),
            _buildAlternativeItem(
              'Physical Activity',
              'Go for a walk, exercise, or stretch',
              Icons.fitness_center,
            ),
            _buildAlternativeItem(
              'Creative Work',
              'Drawing, writing, or music',
              Icons.palette,
            ),
            _buildAlternativeItem(
              'Social Connection',
              'Call a friend or family member',
              Icons.phone,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlternativeItem(
    String title,
    String description,
    IconData icon,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        description,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  void _showUsageStats(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your Usage Pattern',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This feature will show detailed usage analytics in the future.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringCapitalize on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
