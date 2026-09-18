import 'package:flutter/material.dart';
import 'dart:math' as math;

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  // --- Static sample data ---
  static const Duration _todayScreenTime = Duration(hours: 4, minutes: 26);
  static const int _focusSessions = 3;
  static const int _blocksToday = 47;
  static const double _avgDailyHours = 4.6;
  // static const double _goalHours = 4.0;

  // Advanced Insights data
  static const int _scrollEvents = 142;
  static const int _appSwitches = 28;
  static const int _lastBedtime = 1;
  static const int _sleepDuration = 6;

  // static const List<double> _weeklyUsageHours = [
  //   3.2,
  //   3.8,
  //   4.5,
  //   4.8,
  //   5.2,
  //   4.8,
  //   5.5,
  // ];
  // static const List<String> _weekDays = [
  //   'Mon',
  //   'Mon',
  //   'Tue',
  //   'Tue',
  //   'Wed',
  //   'Wed',
  //   'Thu',
  //   'Thu',
  //   'Fri',
  //   'Fri',
  //   'Sat',
  //   'Sat',
  //   'Sun',
  // ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header(),
            const SizedBox(height: 20),

            // Hero card - Today's Screen Time
            _HeroCard(
              title: "Today's Screen Time",
              value: _formatDuration(_todayScreenTime),
              subtitle: 'Keep it balanced',
            ),

            const SizedBox(height: 16),

            // Two stat cards
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Focus Sessions',
                    value: _focusSessions.toString(),
                    icon: Icons.access_time,
                    color: Colors.cyan,
                    borderColor: Colors.cyan.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    title: 'Blocks Today',
                    value: _blocksToday.toString(),
                    icon: Icons.block,
                    color: Colors.orange,
                    borderColor: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),

            // Line chart
            const SizedBox(height: 24),
            const _SectionTitle('Advanced Insights'),
            const SizedBox(height: 12),

            // Enhanced Circular progress cards with calculated metrics
            _AdvancedInsightsSection(
              doomScrollScore: _calculateDoomScrollRisk(
                _scrollEvents,
                _appSwitches,
              ),
              sleepImpactScore: _calculateSleepImpact(
                _sleepDuration,
                _lastBedtime,
                _avgDailyHours,
              ),
              scrollEvents: _scrollEvents,
              appSwitches: _appSwitches,
              sleepHours: _sleepDuration,
            ),

            const SizedBox(height: 24),

            // Balance Score Card
            const _BalanceScoreCard(score: 32, rating: 'Fair'),

            const SizedBox(height: 24),
            const _SectionTitle('Focus Recap'),
            const SizedBox(height: 12),

            // Before/After Comparison
            Row(
              children: [
                Expanded(
                  child: _FocusRecapCard(
                    title: 'Before',
                    color: Colors.red,
                    metrics: const [
                      {'label': 'App Switches', 'value': '14', 'change': ''},
                      {'label': 'Avg. Duration', 'value': '6m', 'change': ''},
                      {'label': 'Scroll Events', 'value': '30', 'change': ''},
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FocusRecapCard(
                    title: 'After',
                    color: Colors.green,
                    metrics: const [
                      {
                        'label': 'App Switches',
                        'value': '10',
                        'change': '↓ 28%',
                      },
                      {
                        'label': 'Avg. Duration',
                        'value': '12m',
                        'change': '↑ 71%',
                      },
                      {
                        'label': 'Scroll Events',
                        'value': '5',
                        'change': '↓ 83%',
                      },
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const _SectionTitle('Small Wins to Try'),
            const SizedBox(height: 12),

            // Suggestions
            const _SuggestionTile(
              icon: Icons.nightlight_round,
              iconColor: Colors.green,
              title: 'Wind-down at 11:00 PM',
              description: 'Dim screen + avoid feeds 45 mins before bed.',
            ),
            const SizedBox(height: 12),
            const _SuggestionTile(
              icon: Icons.timer_outlined,
              iconColor: Colors.green,
              title: '15-min Feed Limit',
              description: 'One short window; then auto-enter Focus Mode.',
            ),
            const SizedBox(height: 12),
            const _SuggestionTile(
              icon: Icons.directions_walk,
              iconColor: Colors.green,
              title: 'Micro-breaks',
              description: 'Stand up every 45 mins; reset attention.',
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Start Focus Mode',
                    icon: Icons.spa_outlined,
                    backgroundColor: Colors.white,
                    textColor: Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Set Bedtime',
                    icon: Icons.access_time,
                    backgroundColor: Colors.grey.shade900,
                    textColor: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }

  /// Calculate doom-scroll risk score (0-100)
  /// Based on scroll events and app switches
  static int _calculateDoomScrollRisk(int scrollEvents, int appSwitches) {
    // Formula: Higher scroll events + app switches = higher doom-scroll risk
    // Normalize: every 50 scroll events = 25 risk points
    // Normalize: every 10 app switches = 25 risk points
    int scrollRisk = ((scrollEvents / 50) * 25).toInt().clamp(0, 50);
    int switchRisk = ((appSwitches / 10) * 25).toInt().clamp(0, 50);
    return (scrollRisk + switchRisk).clamp(0, 100);
  }

  /// Calculate sleep impact score (0-100)
  /// Based on sleep duration and late-night screen time
  static int _calculateSleepImpact(
    int sleepHours,
    int lastBedtimeHours,
    double dailyHours,
  ) {
    // Formula: Less sleep + high daily screen time = high sleep impact
    int sleepScore = 0;

    // Sleep duration impact: ideal 7-8 hours
    if (sleepHours < 5) {
      sleepScore = 90;
    } else if (sleepHours < 6) {
      sleepScore = 70;
    } else if (sleepHours < 7) {
      sleepScore = 50;
    } else if (sleepHours < 8) {
      sleepScore = 30;
    } else {
      sleepScore = 10;
    }

    // Late-night screen time penalty
    if (lastBedtimeHours <= 2) {
      sleepScore = (sleepScore * 1.3).toInt().clamp(0, 100);
    }

    // High daily usage increases impact
    if (dailyHours > 5) {
      sleepScore = (sleepScore * 1.2).toInt().clamp(0, 100);
    }

    return sleepScore.clamp(0, 100);
  }
}

// --- UI Pieces ---

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.favorite, color: cs.primary, size: 24),
            const SizedBox(width: 10),
            const Text(
              'Digital Health',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Text(
          'Awareness first',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _HeroCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.phone_android,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color borderColor;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }
}

// class _WeeklyUsageChart extends StatelessWidget {
//   final List<double> data;
//   final double avgHours;
//   final double goalHours;
//   final List<String> days;

//   const _WeeklyUsageChart({
//     required this.data,
//     required this.avgHours,
//     required this.goalHours,
//     required this.days,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: cs.surface,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
//       ),
//       child: Column(
//         children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Row(
//                 children: [
//                   Icon(
//                     Icons.trending_up,
//                     size: 18,
//                     color: cs.onSurface.withValues(alpha: 0.7),
//                   ),
//                   const SizedBox(width: 6),
//                   Text(
//                     'Avg ${avgHours}h / day',
//                     style: TextStyle(
//                       color: cs.onSurface.withValues(alpha: 0.7),
//                       fontSize: 14,
//                     ),
//                   ),
//                 ],
//               ),
//               Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 12,
//                   vertical: 6,
//                 ),
//                 decoration: BoxDecoration(
//                   color: Colors.green.withValues(alpha: 0.15),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: const Text(
//                   'Week',
//                   style: TextStyle(
//                     color: Colors.green,
//                     fontSize: 12,
//                     fontWeight: FontWeight.w600,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 20),
//           SizedBox(
//             height: 180,
//             child: CustomPaint(
//               size: Size.infinite,
//               painter: _LineChartPainter(
//                 data: data,
//                 avgLine: avgHours,
//                 goalLine: goalHours,
//                 primaryColor: Colors.green,
//               ),
//             ),
//           ),
//           const SizedBox(height: 12),
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: days.map((day) {
//               return Text(
//                 day,
//                 style: TextStyle(
//                   fontSize: 11,
//                   color: cs.onSurface.withValues(alpha: 0.6),
//                 ),
//               );
//             }).toList(),
//           ),
//         ],
//       ),
//     );
//   }
// }

// Advanced Insights Section with calculated metrics
class _AdvancedInsightsSection extends StatelessWidget {
  final int doomScrollScore;
  final int sleepImpactScore;
  final int scrollEvents;
  final int appSwitches;
  final int sleepHours;

  const _AdvancedInsightsSection({
    required this.doomScrollScore,
    required this.sleepImpactScore,
    required this.scrollEvents,
    required this.appSwitches,
    required this.sleepHours,
  });

  String _getRiskLevel(int score) {
    if (score >= 70) return 'High';
    if (score >= 40) return 'Moderate';
    return 'Low';
  }

  Color _getRiskColor(int score) {
    if (score >= 70) return Colors.redAccent;
    if (score >= 40) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    final doomColor = _getRiskColor(doomScrollScore);
    final sleepColor = _getRiskColor(sleepImpactScore);
    final doomLevel = _getRiskLevel(doomScrollScore);
    final sleepLevel = _getRiskLevel(sleepImpactScore);

    return Column(
      children: [
        // Circular progress cards with enhanced styling
        Row(
          children: [
            Expanded(
              child: _EnhancedCircularCard(
                value: doomScrollScore,
                color: doomColor,
                title: 'Doom-Scroll\nRisk',
                level: doomLevel,
                icon: Icons.swipe_down_alt,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EnhancedCircularCard(
                value: sleepImpactScore,
                color: sleepColor,
                title: 'Sleep\nImpact',
                level: sleepLevel,
                icon: Icons.bedtime,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Enhanced Circular Card with title and level
class _EnhancedCircularCard extends StatelessWidget {
  final int value;
  final Color color;
  final String title;
  final String level;
  final IconData icon;

  const _EnhancedCircularCard({
    required this.value,
    required this.color,
    required this.title,
    required this.level,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular progress
          SizedBox(
            width: 90,
            height: 90,
            child: CustomPaint(
              painter: _CircularProgressPainter(
                progress: value / 100,
                color: color,
                backgroundColor: cs.outline.withValues(alpha: 0.1),
              ),
              child: Center(
                child: Text(
                  value.toString(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: color,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w400,
              height: 1.2,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for line chart
// class _LineChartPainter extends CustomPainter {
//   final List<double> data;
//   final double avgLine;
//   final double goalLine;
//   final Color primaryColor;

//   _LineChartPainter({
//     required this.data,
//     required this.avgLine,
//     required this.goalLine,
//     required this.primaryColor,
//   });

//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..color = primaryColor
//       ..strokeWidth = 3
//       ..style = PaintingStyle.stroke
//       ..strokeCap = StrokeCap.round;

//     final fillPaint = Paint()
//       ..color = primaryColor.withValues(alpha: 0.1)
//       ..style = PaintingStyle.fill;

//     final dashedPaint = Paint()
//       ..color = Colors.grey.withValues(alpha: 0.3)
//       ..strokeWidth = 1.5
//       ..style = PaintingStyle.stroke;

//     final maxValue = data.reduce(math.max);
//     final minValue = data.reduce(math.min);
//     final range = maxValue - minValue;

//     final path = Path();
//     final fillPath = Path();

//     // Draw dashed lines for avg and goal
//     final avgY = size.height - ((avgLine - minValue) / range) * size.height;
//     final goalY = size.height - ((goalLine - minValue) / range) * size.height;

//     _drawDashedLine(
//       canvas,
//       dashedPaint,
//       Offset(0, avgY),
//       Offset(size.width, avgY),
//     );
//     _drawDashedLine(
//       canvas,
//       dashedPaint,
//       Offset(0, goalY),
//       Offset(size.width, goalY),
//     );

//     // Draw line chart
//     final stepX = size.width / (data.length - 1);

//     for (int i = 0; i < data.length; i++) {
//       final x = i * stepX;
//       final y = size.height - ((data[i] - minValue) / range) * size.height;

//       if (i == 0) {
//         path.moveTo(x, y);
//         fillPath.moveTo(x, size.height);
//         fillPath.lineTo(x, y);
//       } else {
//         path.lineTo(x, y);
//         fillPath.lineTo(x, y);
//       }
//     }

//     fillPath.lineTo(size.width, size.height);
//     fillPath.close();

//     canvas.drawPath(fillPath, fillPaint);
//     canvas.drawPath(path, paint);

//     // Draw dots
//     final dotPaint = Paint()
//       ..color = primaryColor
//       ..style = PaintingStyle.fill;

//     for (int i = 0; i < data.length; i++) {
//       final x = i * stepX;
//       final y = size.height - ((data[i] - minValue) / range) * size.height;
//       canvas.drawCircle(Offset(x, y), 4, dotPaint);
//     }

//     // Draw labels
//     final textPainter = TextPainter(textDirection: TextDirection.ltr);

//     textPainter.text = TextSpan(
//       text: 'avg ${avgLine}h',
//       style: const TextStyle(color: Colors.grey, fontSize: 10),
//     );
//     textPainter.layout();
//     textPainter.paint(canvas, Offset(size.width - 60, avgY - 20));

//     textPainter.text = TextSpan(
//       text: 'goal ${goalLine}h',
//       style: const TextStyle(color: Colors.grey, fontSize: 10),
//     );
//     textPainter.layout();
//     textPainter.paint(canvas, Offset(size.width - 60, goalY + 8));
//   }

//   void _drawDashedLine(Canvas canvas, Paint paint, Offset start, Offset end) {
//     const dashWidth = 5;
//     const dashSpace = 5;
//     double distance = (end - start).distance;
//     double dashCount = distance / (dashWidth + dashSpace);

//     for (int i = 0; i < dashCount; i++) {
//       double startX =
//           start.dx +
//           (end.dx - start.dx) * (i * (dashWidth + dashSpace) / distance);
//       double startY =
//           start.dy +
//           (end.dy - start.dy) * (i * (dashWidth + dashSpace) / distance);
//       double endX =
//           start.dx +
//           (end.dx - start.dx) *
//               ((i * (dashWidth + dashSpace) + dashWidth) / distance);
//       double endY =
//           start.dy +
//           (end.dy - start.dy) *
//               ((i * (dashWidth + dashSpace) + dashWidth) / distance);
//       canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
//     }
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }

// Custom painter for circular progress
class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - 5, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 5),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Balance Score Card
class _BalanceScoreCard extends StatelessWidget {
  final int score;
  final String rating;

  const _BalanceScoreCard({required this.score, required this.rating});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.purple.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Balance Score',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CustomPaint(
                  painter: _CircularProgressPainter(
                    progress: score / 100,
                    color: Colors.purple,
                    backgroundColor: cs.outline.withValues(alpha: 0.1),
                  ),
                  child: Center(
                    child: Text(
                      score.toString(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rating,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Overall Health',
                      style: TextStyle(
                        color: Colors.purple,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Focus Recap Card
class _FocusRecapCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<Map<String, String>> metrics;

  const _FocusRecapCard({
    required this.title,
    required this.color,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                title == 'Before' ? Icons.trending_down : Icons.trending_up,
                color: color,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...metrics.map(
            (metric) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    metric['label']!,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        metric['value']!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (metric['change']!.isNotEmpty)
                        Text(
                          metric['change']!,
                          style: TextStyle(
                            fontSize: 11,
                            color: metric['change']!.startsWith('↓')
                                ? Colors.green
                                : Colors.blue,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Suggestion Tile
class _SuggestionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _SuggestionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Action Button
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color textColor;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
