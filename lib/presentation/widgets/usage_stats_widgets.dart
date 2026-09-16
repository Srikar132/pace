import 'package:flutter/material.dart';
import 'package:pace/models/usage_stats_models.dart';
import 'dart:typed_data';

/// Widget for displaying individual app usage in a list tile
class UsageAppListTile extends StatelessWidget {
  final AppUsageStats app;

  const UsageAppListTile({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        tileColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: _buildAppIcon(),
        title: Row(
          children: [
            Expanded(
              child: Text(
                app.appName,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildCategoryDot(),
          ],
        ),
        subtitle: Text(
          app.category.displayName,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF8A8A8A),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              app.formattedUsageTime,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (app.sessions > 0) ...[
              const SizedBox(height: 2),
              Text(
                '${app.sessions} session${app.sessions == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8A8A8A),
                ),
              ),
            ],
          ],
        ),
        onTap: () {
          // TODO: Navigate to detailed app stats
          _showAppDetailsModal(context);
        },
      ),
    );
  }

  Widget _buildAppIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: app.appIcon != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  Uint8List.fromList(app.appIcon!.codeUnits),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildFallbackIcon();
                  },
                ),
              )
            : _buildFallbackIcon(),
      ),
    );
  }

  Widget _buildFallbackIcon() {
    return Icon(Icons.apps, color: const Color(0xFF7ED957), size: 24);
  }

  Widget _buildCategoryDot() {
    Color dotColor;
    switch (app.category) {
      case AppCategory.distracting:
        dotColor = const Color(0xFFFF8C00); // Orange
        break;
      case AppCategory.productive:
        dotColor = const Color(0xFF7ED957); // Green
        break;
      case AppCategory.others:
        dotColor = const Color(0xFF8A8A8A); // Grey
        break;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
    );
  }

  void _showAppDetailsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => AppDetailsModal(app: app),
    );
  }
}

/// Modal showing detailed app usage statistics
class AppDetailsModal extends StatelessWidget {
  final AppUsageStats app;

  const AppDetailsModal({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.apps,
                  color: const Color(0xFF7ED957),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.appName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      app.category.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF8A8A8A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Usage stats
          _buildStatRow(
            'Total Usage',
            app.formattedUsageTime,
            Icons.access_time,
            theme,
          ),

          const SizedBox(height: 16),

          _buildStatRow('Sessions', '${app.sessions}', Icons.launch, theme),

          const SizedBox(height: 16),

          _buildStatRow(
            'Last Used',
            _formatLastUsed(app.lastUsedDateTime),
            Icons.schedule,
            theme,
          ),

          const SizedBox(height: 32),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: Add to focus session blocklist
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.block),
                  label: const Text('Block'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Close'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          // Safe area padding
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    String label,
    String value,
    IconData icon,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF7ED957), size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF8A8A8A),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatLastUsed(DateTime lastUsed) {
    final now = DateTime.now();
    final difference = now.difference(lastUsed);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

/// Widget for displaying weekly usage chart
class WeeklyUsageChart extends StatelessWidget {
  final List<DailyUsageChartData> data;

  const WeeklyUsageChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxUsage = data.isNotEmpty
        ? data.map((d) => d.totalMinutes).reduce((a, b) => a > b ? a : b)
        : 100;

    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        children: [
          // Chart title
          Row(
            children: [
              Text(
                'Weekly Overview',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(maxUsage / 60).toStringAsFixed(1)}h peak',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8A8A8A),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Chart
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: data.map((dayData) {
                return _buildChartBar(dayData, maxUsage, theme);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartBar(
    DailyUsageChartData dayData,
    int maxUsage,
    ThemeData theme,
  ) {
    final barHeight = maxUsage > 0
        ? (dayData.totalMinutes / maxUsage) * 120
        : 0.0;
    final distractingHeight = maxUsage > 0
        ? (dayData.distractingMinutes / maxUsage) * 120
        : 0.0;
    final productiveHeight = maxUsage > 0
        ? (dayData.productiveMinutes / maxUsage) * 120
        : 0.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Bar
        Container(
          width: 24,
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Others (grey) - full height of used portion
              if (dayData.totalMinutes > 0)
                Container(
                  width: 24,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A6A6A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

              // Productive (green) - from bottom
              if (dayData.productiveMinutes > 0)
                Container(
                  width: 24,
                  height: productiveHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7ED957),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

              // Distracting (orange) - from bottom, stacked on productive
              if (dayData.distractingMinutes > 0)
                Positioned(
                  bottom: productiveHeight,
                  child: Container(
                    width: 24,
                    height: distractingHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8C00),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Day label
        Text(
          dayData.day,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF8A8A8A),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Loading shimmer for usage stats
class UsageStatsLoadingShimmer extends StatefulWidget {
  const UsageStatsLoadingShimmer({super.key});

  @override
  State<UsageStatsLoadingShimmer> createState() =>
      _UsageStatsLoadingShimmerState();
}

class _UsageStatsLoadingShimmerState extends State<UsageStatsLoadingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ListView.builder(
          itemCount: 8,
          padding: const EdgeInsets.all(16),
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // Icon shimmer
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFF2A2A2A),
                        const Color(0xFF3A3A3A),
                        _animation.value,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Text shimmer
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              const Color(0xFF2A2A2A),
                              const Color(0xFF3A3A3A),
                              _animation.value,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 100,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              const Color(0xFF2A2A2A),
                              const Color(0xFF3A3A3A),
                              _animation.value,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Time shimmer
                  Container(
                    width: 60,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFF2A2A2A),
                        const Color(0xFF3A3A3A),
                        _animation.value,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
