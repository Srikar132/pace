import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/presentation/overlays/providers/overlay_provider.dart';
import 'package:pace/presentation/overlays/widgets/focus_timer_widget.dart';
import 'package:pace/presentation/overlays/widgets/overlay_background.dart';

class BlockedShortsOverlay extends ConsumerStatefulWidget {
  const BlockedShortsOverlay({super.key});

  @override
  ConsumerState<BlockedShortsOverlay> createState() =>
      _BlockedShortsOverlayState();
}

class _BlockedShortsOverlayState extends ConsumerState<BlockedShortsOverlay>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _bounceController;
  late AnimationController _textController;

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _textController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Start animations
    _bounceController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      _textController.forward();
    });

    // Double vibration for shorts
    Future.microtask(() {
      ref.read(overlayDataProvider.notifier).vibrate('double');
    });

    // Auto-dismiss after 2 seconds - close activity and return to YouTube
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        ref.read(overlayDataProvider.notifier).closeOverlay();
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _bounceController.dispose();
    _textController.dispose();
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

    final contentType =
        overlayState.overlayData['contentType'] as String? ?? 'Short Content';
    final platform =
        overlayState.overlayData['platform'] as String? ?? 'Unknown';

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: OverlayBackground(
          gradient: _getPlatformGradient(platform),
          child: SafeArea(
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: _bounceController,
                curve: Curves.elasticOut,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated wave effect with platform icon
                    _buildWaveAnimation(platform),

                    const SizedBox(height: 32),

                    // Content type blocked message
                    FadeTransition(
                      opacity: _textController,
                      child: _buildBlockMessage(contentType),
                    ),

                    const SizedBox(height: 24),

                    // Focus timer
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.5),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _textController,
                              curve: Curves.easeOut,
                            ),
                          ),
                      child: FocusTimerWidget(
                        elapsedMinutes: overlayState.focusTimeMinutes,
                        sessionType: overlayState.sessionType,
                        compact: true,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Educational content card
                    /*SlideTransition(
                      position:  Tween<Offset>(
                        begin: const Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _textController,
                        curve: Curves.easeOut,
                      )),
                      child: EducationalContentCard(
                        title:  'Digital Wellness Tip',
                        message: educationalMessage,
                        icon: Icons.psychology,
                        color: Colors.orange,
                      ),
                    ),*/
                    const SizedBox(height: 24),

                    // Platform-specific tips
                    /*SlideTransition(
                      position:  Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset. zero,
                      ).animate(CurvedAnimation(
                        parent: _textController,
                        curve: Curves.easeOut,
                      )),
                      child: PlatformSpecificTips(platform: platform),
                    ),*/
                    const SizedBox(height: 32),

                    // Quick action buttons
                    FadeTransition(
                      opacity: _textController,
                      child: _buildQuickActions(overlayNotifier),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaveAnimation(String platform) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer wave
        AnimatedBuilder(
          animation: _waveController,
          builder: (context, child) {
            return Container(
              width: 180 + (_waveController.value * 40),
              height: 180 + (_waveController.value * 40),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getPlatformColor(
                    platform,
                  ).withValues(alpha: 0.3 - (_waveController.value * 0.3)),
                  width: 2,
                ),
              ),
            );
          },
        ),

        // Inner wave
        AnimatedBuilder(
          animation: _waveController,
          builder: (context, child) {
            return Container(
              width: 130 + (_waveController.value * 25),
              height: 130 + (_waveController.value * 25),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getPlatformColor(
                    platform,
                  ).withValues(alpha: 0.5 - (_waveController.value * 0.5)),
                  width: 3,
                ),
              ),
            );
          },
        ),

        // Center icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _getPlatformColor(platform),
            boxShadow: [
              BoxShadow(
                color: _getPlatformColor(platform).withValues(alpha: 0.6),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Icon(
            _getPlatformIcon(platform),
            size: 40,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildBlockMessage(String contentType) {
    return Column(
      children: [
        Text(
          '$contentType Blocked! ',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
          ),
          child: const Text(
            'Addictive Content Detected',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(OverlayDataNotifier notifier) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildQuickActionButton(
          icon: Icons.close,
          label: 'Continue',
          color: Colors.green,
          onPressed: () =>
              notifier.closeOverlay(), // Close activity and return to YouTube
        ),
        _buildQuickActionButton(
          icon: Icons.arrow_back,
          label: 'Back',
          color: Colors.blue,
          onPressed: () => notifier.goBack(),
        ),
        _buildQuickActionButton(
          icon: Icons.info_outline,
          label: 'Learn',
          color: Colors.purple,
          onPressed: () => notifier.showEducationalContent('blocked_shorts'),
        ),
      ],
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.2),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  LinearGradient _getPlatformGradient(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF2D1B1B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'instagram':
        return const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF2A1A2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'tiktok':
        return const LinearGradient(
          colors: [Color(0xFF000000), Color(0xFF0D0D0D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF0F0F0F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Colors.red;
      case 'instagram':
        return Colors.purple;
      case 'tiktok':
        return Colors.pink;
      case 'facebook':
        return Colors.blue;
      case 'snapchat':
        return Colors.yellow;
      default:
        return Colors.orange;
    }
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Icons.play_circle_outline;
      case 'instagram':
        return Icons.camera_alt;
      case 'tiktok':
        return Icons.music_note;
      case 'facebook':
        return Icons.video_library;
      case 'snapchat':
        return Icons.photo_camera;
      default:
        return Icons.videocam_off;
    }
  }
}
