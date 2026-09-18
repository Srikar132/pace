import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class FocusTimerWidget extends StatelessWidget {
  final int elapsedMinutes;
  final String sessionType;
  final bool compact;

  const FocusTimerWidget({
    super.key,
    required this.elapsedMinutes,
    required this.sessionType,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.accent, AppColors.accentMuted],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getTimerIcon(sessionType),
            color: Colors.white,
            size: compact ? 20 : 24,
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Focus Time',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _formatTime(elapsedMinutes),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getTimerIcon(String sessionType) {
    switch (sessionType.toLowerCase()) {
      case 'timer':
        return Icons.timer;
      case 'stopwatch':
        return Icons.access_time;
      case 'pomodoro':
        return Icons.schedule;
      default:
        return Icons.timer;
    }
  }

  String _formatTime(int minutes) {
    if (minutes < 60) {
      return '${minutes}m';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '${hours}h ${mins}m';
    }
  }
}
