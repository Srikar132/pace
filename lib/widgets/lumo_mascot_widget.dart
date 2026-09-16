import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:pace/core/constants/images.dart';
import 'package:pace/presentation/screens/lumo_voice_bot_screen.dart';

class LumoMascotWidget extends StatefulWidget {
  final VoidCallback onTap;
  final double size;

  const LumoMascotWidget({
    super.key,
    required this.onTap,
    this.size = 50,
  });

  @override
  State<LumoMascotWidget> createState() => _LumoMascotWidgetState();
}

class _LumoMascotWidgetState extends State<LumoMascotWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late final AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _audioPlayer = AudioPlayer();
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    // Haptic feedback
    HapticFeedback.heavyImpact();

    // Scale animation
    await _controller.forward();
    await _controller.reverse();

    // Play sound (add your sound file to assets/sounds/)
    try {
      await _audioPlayer.play(AssetSource('sounds/lumo-sound.wav'));
    } catch (e) {
      // Sound file not found - silently fail
    }

    // Call parent callback
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onLongPress: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const LumoVoiceBotScreen()));
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).primaryColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: ClipOval(
              child: Image.asset(
                KLumoIcon,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }
}