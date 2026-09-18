import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/core/theme/app_theme.dart';
import 'package:pace/presentation/overlays/providers/overlay_provider.dart';
import 'package:pace/presentation/overlays/widgets/focus_timer_widget.dart';
import 'package:pace/presentation/overlays/widgets/overlay_background.dart';

class BlockedWebsiteOverlay extends ConsumerStatefulWidget {
  const BlockedWebsiteOverlay({super.key});

  @override
  ConsumerState<BlockedWebsiteOverlay> createState() =>
      _BlockedWebsiteOverlayState();
}

class _BlockedWebsiteOverlayState extends ConsumerState<BlockedWebsiteOverlay>
    with TickerProviderStateMixin {
  late AnimationController _shieldController;
  late AnimationController _contentController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _shieldController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _contentController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    // Staggered animation start
    _shieldController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _contentController.forward();
    });

    // Vibrate
    Future.microtask(() {
      ref.read(overlayDataProvider.notifier).vibrate();
    });
  }

  @override
  void dispose() {
    _shieldController.dispose();
    _contentController.dispose();
    _pulseController.dispose();
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

    final domain = overlayState.overlayData['domain'] as String? ?? 'website';

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: OverlayBackground(
          gradient: const LinearGradient(
            colors: [AppColors.background, AppColors.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // Shield animation
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _shieldController,
                      curve: Curves.elasticOut,
                    ),
                    child: _buildShieldIcon(),
                  ),

                  const SizedBox(height: 32),

                  // Block message
                  FadeTransition(
                    opacity: _contentController,
                    child: _buildBlockMessage(domain),
                  ),

                  const SizedBox(height: 24),

                  // Website info card
                  /*SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _contentController,
                      curve: Curves.easeOut,
                    )),
                    child: WebsiteInfoCard(
                      domain: domain,
                      blockReason: blockReason,
                      isSecure: domain.startsWith('https'),
                    ),
                  ),*/
                  const SizedBox(height: 24),

                  // Focus timer
                  SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 0.2),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _contentController,
                            curve: Curves.easeOut,
                          ),
                        ),
                    child: FocusTimerWidget(
                      elapsedMinutes: overlayState.focusTimeMinutes,
                      sessionType: overlayState.sessionType,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Productivity suggestions
                  /*FadeTransition(
                    opacity: _contentController,
                    child: ProductivitySuggestions(
                      domain: domain,
                      suggestion: suggestion,
                    ),
                  ),*/
                  const SizedBox(height: 32),

                  // Action buttons
                  SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 0.3),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _contentController,
                            curve: Curves.easeOut,
                          ),
                        ),
                    child: _buildActionButtons(overlayNotifier),
                  ),

                  const SizedBox(height: 24),

                  // Website blocking stats (if available)
                  _buildBlockingStats(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShieldIcon() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.withValues(
              alpha: 0.1 + (_pulseController.value * 0.1),
            ),
            border: Border.all(
              color: Colors.blue.withValues(
                alpha: 0.5 + (_pulseController.value * 0.3),
              ),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.3),
                blurRadius: 20 + (_pulseController.value * 10),
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(Icons.security, size: 50, color: Colors.blue),
        );
      },
    );
  }

  Widget _buildBlockMessage(String domain) {
    return Column(
      children: [
        const Text(
          'Website Blocked',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
          ),
          child: Text(
            domain,
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'This website is blocked during your focus session',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildActionButtons(OverlayDataNotifier notifier) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => notifier.goHome(),
                icon: const Icon(Icons.home),
                label: const Text('Go to Home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withValues(alpha: 0.2),
                  foregroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Colors.green.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => notifier.goBack(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.withValues(alpha: 0.2),
                  foregroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Colors.orange.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showEndSessionDialog(context, notifier),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('End Focus Session'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBlockingStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.block,
            label: 'Blocked Today',
            value: '23',
          ),
          _buildStatItem(icon: Icons.timer, label: 'Time Saved', value: '1.2h'),
          _buildStatItem(
            icon: Icons.trending_up,
            label: 'Focus Score',
            value: '85%',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _showEndSessionDialog(
    BuildContext context,
    OverlayDataNotifier notifier,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'End Focus Session?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Ending your session now will remove all website blocks. Are you sure? ',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Stay Focused',
              style: TextStyle(color: Colors.blue),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              notifier.endFocusSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }
}
