import 'dart:math' show pi, sin, cos;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/voice_state.dart';
import '../providers/voice_session_provider.dart';

class LumoVoiceBotScreen extends ConsumerStatefulWidget {
  const LumoVoiceBotScreen({super.key});

  @override
  ConsumerState<LumoVoiceBotScreen> createState() => _LumoVoiceBotScreenState();
}

class _LumoVoiceBotScreenState extends ConsumerState<LumoVoiceBotScreen>
    with TickerProviderStateMixin {
  VoiceSessionNotifier? _voiceNotifier;

  late AnimationController _controller;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _glowController.dispose();
    _voiceNotifier?.stopAll();
    super.dispose();
  }

  Future<void> _initialize() async {
    _voiceNotifier = ref.read(voiceSessionProvider.notifier);
    await _voiceNotifier!.initialize();
  }

  void _handleTap() {
    final state = ref.read(voiceSessionProvider).state;
    final notifier = ref.read(voiceSessionProvider.notifier);

    // Simple two-tap flow:
    // 1. Tap when idle → Start continuous conversation
    // 2. Tap anytime during conversation → Stop everything

    if (state == VoiceSessionState.idle || state == VoiceSessionState.error) {
      // Start continuous conversation mode
      notifier.startListening();
    } else {
      // Stop everything - listening, thinking, or speaking
      notifier.interrupt();
    }
  }

  Color _getDotColor(VoiceSessionState state) {
    switch (state) {
      case VoiceSessionState.idle:
        return const Color(0xFF388E3C); // Dark green - ready
      case VoiceSessionState.listening:
        return const Color(0xFF00E676); // Bright neon green - listening
      case VoiceSessionState.thinking:
        return const Color(0xFFFFB74D); // Orange - processing
      case VoiceSessionState.speaking:
        return const Color(0xFF4CAF50); // Medium green - bot speaking
      case VoiceSessionState.error:
        return const Color(0xFFFF5252); // Red - error
      default:
        return const Color(0xFF4CAF50);
    }
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceSessionProvider);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Animated orb with Luma logo
              _buildVoiceOrb(voiceState.state, voiceState.audioLevel),

              // Close button
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white38,
                    size: 28,
                  ),
                ),
              ),

              // Status text at bottom
              Positioned(
                bottom: 100,
                child: _buildStatusIndicator(voiceState.state),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceOrb(VoiceSessionState state, double audioLevel) {
    final Color dotColor = _getDotColor(state);

    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _glowAnimation]),
      builder: (context, child) {
        // Clamp the glow value to prevent opacity issues
        final glowVal = _glowAnimation.value.clamp(0.8, 1.2);

        return SizedBox(
          width: 320,
          height: 320,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Animated green dots
              CustomPaint(
                size: const Size(320, 320),
                painter: GreenDotsPainter(
                  color: dotColor,
                  animationValue: _controller.value,
                  glowValue: glowVal,
                  state: state,
                  soundLevel: audioLevel,
                ),
              ),

              // Center Luma logo - fixed position, no scaling
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(
                        alpha: (0.3 * glowVal).clamp(0.0, 1.0),
                      ),
                      blurRadius: 30,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/luma_logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dotColor.withValues(alpha: 0.3),
                        ),
                        child: Icon(
                          Icons.mic_rounded,
                          color: dotColor,
                          size: 80,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicator(VoiceSessionState state) {
    String text;
    String subText;
    Color textColor;
    bool showDots = false;

    switch (state) {
      case VoiceSessionState.listening:
        text = 'Listening';
        subText = 'Tap to stop';
        textColor = const Color(0xFF00E676);
        showDots = true;
        break;
      case VoiceSessionState.thinking:
        text = 'Processing';
        subText = 'Tap to stop';
        textColor = const Color(0xFFFFB74D);
        showDots = true;
        break;
      case VoiceSessionState.speaking:
        text = 'Lumo';
        subText = 'Tap to stop';
        textColor = const Color(0xFF4CAF50);
        showDots = true;
        break;
      case VoiceSessionState.idle:
        text = 'Tap to speak';
        subText = '';
        textColor = const Color(0xFF388E3C);
        showDots = false;
        break;
      case VoiceSessionState.error:
        text = 'Tap to retry';
        subText = '';
        textColor = const Color(0xFFFF5252);
        showDots = false;
        break;
      default:
        text = 'Tap to speak';
        subText = '';
        textColor = const Color(0xFF388E3C);
        showDots = false;
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            if (showDots) ...[
              const SizedBox(width: 8),
              _buildAnimatedDots(textColor),
            ],
          ],
        ),
        if (subText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 22),
            child: Text(
              subText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAnimatedDots(Color color) {
    return Row(
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return AnimatedOpacity(
              opacity: ((_controller.value * 3) % 3).floor() == index
                  ? 1.0
                  : 0.3,
              duration: const Duration(milliseconds: 300),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

/// Custom painter for animated green dots around the logo
class GreenDotsPainter extends CustomPainter {
  final Color color;
  final double animationValue;
  final double glowValue;
  final VoiceSessionState state;
  final double soundLevel;

  GreenDotsPainter({
    required this.color,
    required this.animationValue,
    required this.glowValue,
    required this.state,
    required this.soundLevel,
  });

  double _safeOpacity(double value) {
    return value.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    // Number of dots based on state
    int dotCount =
        state == VoiceSessionState.listening ||
            state == VoiceSessionState.speaking
        ? 50
        : 35;

    for (int i = 0; i < dotCount; i++) {
      final angle = (i / dotCount) * 2 * pi + (animationValue * 2 * pi);

      // Create wave effect
      final waveOffset = sin(angle * 3 + animationValue * 4 * pi) * 15;
      final distance = radius + waveOffset;

      final x = center.dx + cos(angle) * distance;
      final y = center.dy + sin(angle) * distance;

      // Dot size varies based on state
      double dotSize = 3.0;
      double baseOpacity = 0.7;

      if (state == VoiceSessionState.listening) {
        dotSize = 3.5 + (soundLevel / 8).clamp(0.0, 3.0);
        baseOpacity = 0.85;
      } else if (state == VoiceSessionState.speaking) {
        dotSize = 3.0 + (sin(angle * 3 + animationValue * 6 * pi).abs() * 1.0);
        baseOpacity = 0.7;
      } else if (state == VoiceSessionState.thinking) {
        dotSize = 2.5 + (sin(animationValue * 5 * pi).abs() * 0.5);
        baseOpacity = 0.6;
      }

      final sparkle = sin(angle * 5 + animationValue * 6 * pi) * 0.15;
      final opacity = _safeOpacity(baseOpacity + sparkle);

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), dotSize, paint);

      // Glow effect for active states
      if (state == VoiceSessionState.listening ||
          state == VoiceSessionState.speaking) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: _safeOpacity(opacity * 0.25))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, y), dotSize * 2, glowPaint);
      }
    }

    // Inner ring of smaller dots
    final innerRadius = radius * 0.65;
    for (int i = 0; i < 16; i++) {
      final angle = (i / 16) * 2 * pi - (animationValue * 1.5 * pi);
      final x = center.dx + cos(angle) * innerRadius;
      final y = center.dy + sin(angle) * innerRadius;

      final paint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), 2.0, paint);
    }
  }

  @override
  bool shouldRepaint(GreenDotsPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.state != state ||
        oldDelegate.soundLevel != soundLevel;
  }
}
