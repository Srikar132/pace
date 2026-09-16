import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/data/models/app_limit_model.dart';
import 'package:pace/presentation/providers/app_limits_provider.dart';
import 'package:pace/presentation/screens/add_app_limit_screen.dart';
import 'package:pace/services/app_limit_native_service.dart';
import 'package:pace/services/auth_service.dart';

class AppLimitsScreen extends ConsumerStatefulWidget {
  const AppLimitsScreen({super.key});

  @override
  ConsumerState<AppLimitsScreen> createState() => _AppLimitsScreenState();
}

class _AppLimitsScreenState extends ConsumerState<AppLimitsScreen> {
  final _nativeService = AppLimitNativeService();
  Map<String, Map<String, dynamic>> _usageStats = {};
  bool _isLoadingUsage = false;

  @override
  void initState() {
    super.initState();
    _loadUsageStats();
  }

  Future<void> _loadUsageStats() async {
    setState(() => _isLoadingUsage = true);
    try {
      final stats = await _nativeService.getAppUsageStats();
      setState(() {
        _usageStats = stats;
        _isLoadingUsage = false;
      });
    } catch (e) {
      setState(() => _isLoadingUsage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading usage stats: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authServiceProvider).currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to manage app limits')),
      );
    }

    final appLimitsAsync = ref.watch(appLimitsProvider(user.uid));

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Limits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsageStats,
            tooltip: 'Refresh usage stats',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(context),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: appLimitsAsync.when(
        data: (limits) => _buildLimitsList(context, limits, user.uid),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(appLimitsProvider(user.uid)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAddLimit(context, user.uid),
        icon: const Icon(Icons.add),
        label: const Text('Add Limit'),
      ),
    );
  }

  Widget _buildLimitsList(
    BuildContext context,
    List<AppLimitModel> limits,
    String userId,
  ) {
    if (limits.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No app limits set',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to add your first limit',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Sort limits: active first, then by app name
    final sortedLimits = List<AppLimitModel>.from(limits)
      ..sort((a, b) {
        if (a.isActive != b.isActive) {
          return a.isActive ? -1 : 1;
        }
        return a.appName.compareTo(b.appName);
      });

    return RefreshIndicator(
      onRefresh: _loadUsageStats,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedLimits.length,
        itemBuilder: (context, index) {
          final limit = sortedLimits[index];
          final usage = _usageStats[limit.packageName];
          return _AppLimitCard(
            limit: limit,
            userId: userId,
            usage: usage,
            onTap: () => _navigateToEditLimit(context, userId, limit),
            onDelete: () => _deleteLimit(context, userId, limit.packageName),
            onToggle: (value) => _toggleLimit(userId, limit.packageName, value),
          );
        },
      ),
    );
  }

  Future<void> _navigateToAddLimit(BuildContext context, String userId) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddAppLimitScreen(userId: userId),
      ),
    );

    if (result == true && mounted) {
      _loadUsageStats();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App limit added successfully')),
      );
    }
  }

  Future<void> _navigateToEditLimit(
    BuildContext context,
    String userId,
    AppLimitModel limit,
  ) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddAppLimitScreen(userId: userId, existingLimit: limit),
      ),
    );

    if (result == true && mounted) {
      _loadUsageStats();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App limit updated successfully')),
      );
    }
  }

  Future<void> _toggleLimit(
    String userId,
    String packageName,
    bool value,
  ) async {
    try {
      await ref
          .read(appLimitNotifierProvider.notifier)
          .toggleAppLimitStatus(userId, packageName, value);

      // Update native service
      final limits = ref.read(appLimitsProvider(userId)).value ?? [];
      await _nativeService.setAppLimits(limits);

      _loadUsageStats();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error toggling limit: $e')));
      }
    }
  }

  Future<void> _deleteLimit(
    BuildContext context,
    String userId,
    String packageName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Limit'),
        content: const Text('Are you sure you want to delete this app limit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(appLimitNotifierProvider.notifier)
          .deleteAppLimit(userId, packageName);

      // Remove from native service
      await _nativeService.removeAppLimit(packageName);

      _loadUsageStats();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('App limit deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting limit: $e')));
      }
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App Limits Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sync All Limits'),
              subtitle: const Text('Sync limits with native service'),
              onTap: () async {
                Navigator.pop(context);
                await _syncLimitsToNative();
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Clear Warnings'),
              subtitle: const Text('Reset all warning notifications'),
              onTap: () async {
                Navigator.pop(context);
                await _nativeService.clearAllWarnings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Warnings cleared')),
                  );
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncLimitsToNative() async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;

    try {
      final limits = ref.read(appLimitsProvider(user.uid)).value ?? [];
      await _nativeService.setAppLimits(limits);
      await _nativeService.forceCheckLimits();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Limits synced successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error syncing limits: $e')));
      }
    }
  }
}

class _AppLimitCard extends StatelessWidget {
  final AppLimitModel limit;
  final String userId;
  final Map<String, dynamic>? usage;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  const _AppLimitCard({
    required this.limit,
    required this.userId,
    required this.usage,
    required this.onTap,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final usedMinutes = usage?['todayUsageMinutes'] as int? ?? 0;
    final percentage = limit.dailyLimit > 0
        ? (usedMinutes / limit.dailyLimit * 100).clamp(0, 100).toInt()
        : 0;

    final isExceeded = usedMinutes >= limit.dailyLimit && limit.dailyLimit > 0;
    final isNearLimit = percentage >= 75;

    Color getProgressColor() {
      if (isExceeded) return Colors.red;
      if (isNearLimit) return Colors.orange;
      return Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: limit.isActive ? 2 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // App icon placeholder
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color:
                          Colors.primaries[limit.appName.hashCode %
                              Colors.primaries.length],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        limit.appName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          limit.appName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: limit.isActive ? null : Colors.grey,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$usedMinutes / ${limit.dailyLimit} min today',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: getProgressColor(),
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Switch(value: limit.isActive, onChanged: onToggle),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(getProgressColor()),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$percentage% used',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      _ActionChip(
                        label: limit.actionOnExceed.toUpperCase(),
                        color: _getActionColor(limit.actionOnExceed),
                      ),
                      if (limit.weeklyLimit > 0) ...[
                        const SizedBox(width: 8),
                        _ActionChip(
                          label: 'WEEKLY: ${limit.weeklyLimit}m',
                          color: Colors.blue,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'block':
        return Colors.red;
      case 'warn':
        return Colors.orange;
      case 'notify':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;

  const _ActionChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
