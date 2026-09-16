import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/app_limits_provider.dart';
import 'package:pace/presentation/providers/blocked_content_provider.dart';
import 'package:pace/presentation/providers/permission_provider.dart';
import 'package:pace/presentation/providers/parental_control_provider.dart';
import 'package:pace/data/models/blocked_content_model.dart';
import 'package:pace/data/models/app_limit_model.dart';
import 'package:pace/services/blocks_native_service.dart';
import 'package:pace/services/app_limit_native_service.dart';
import 'package:pace/services/native_service.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:pace/widgets/parental_control_dialogs.dart';
import 'dart:async';

// Standalone permission check function accessible by all widgets
Future<bool> _checkAndRequestPermissions(
  BuildContext context,
  WidgetRef ref,
) async {
  print('🔐 Checking accessibility permission...');

  // Check accessibility permission using provider
  final permissionNotifier = ref.read(permissionProvider.notifier);
  await permissionNotifier.checkPermissions();

  final hasAccessibility = ref.read(permissionProvider).accessibilityPermission;
  print('🔐 Accessibility permission: $hasAccessibility');

  if (!hasAccessibility) {
    if (context.mounted) {
      print('🔐 Showing permission dialog...');
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Accessibility Permission Required',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This feature requires Accessibility Service to block content.\n\n'
            'Please enable "Pace" in Accessibility settings.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                print('🔐 User cancelled permission request');
                Navigator.pop(context, false);
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                print('🔐 User accepted - opening settings');
                Navigator.pop(context, true);
              },
              child: const Text(
                'Open Settings',
                style: TextStyle(color: Color(0xFF82D65D)),
              ),
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        print('🔐 Requesting accessibility permission...');
        await permissionNotifier.requestAccessibilityPermission();
        // Wait a bit for user to potentially grant permission
        await Future.delayed(const Duration(seconds: 2));
        // Re-check permission
        await permissionNotifier.checkPermissions();
        final finalPermission = ref
            .read(permissionProvider)
            .accessibilityPermission;
        print('🔐 Final permission status: $finalPermission');
        return finalPermission;
      } else {
        print('🔐 User did not request permission');
      }
    }
    return false;
  }

  print('🔐 Permission already granted');
  return true;
}

// Check and request Usage Stats permission (required for app limits)
Future<bool> _checkAndRequestUsageStatsPermission(BuildContext context) async {
  print('📊 Checking usage stats permission...');

  final hasPermission = await NativeService.hasUsageStatsPermission();
  print('📊 Usage stats permission: $hasPermission');

  if (!hasPermission && context.mounted) {
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.access_time, color: Color(0xFF82D65D), size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Usage Access Required',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'App Limits require Usage Access permission to track how long you use apps.\n\n'
          'This permission allows Pace to:\n'
          '• Monitor app usage time\n'
          '• Enforce daily limits\n'
          '• Show accurate usage statistics\n\n'
          'Please grant "Usage Access" in the next screen.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF82D65D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );

    if (shouldRequest == true) {
      print('📊 Opening usage stats settings...');
      await NativeService.requestUsageStatsPermission();
      await Future.delayed(const Duration(seconds: 2));
      final finalPermission = await NativeService.hasUsageStatsPermission();
      print('📊 Final usage stats permission: $finalPermission');
      return finalPermission;
    }
  }

  return hasPermission;
}

class BlocksScreen extends ConsumerStatefulWidget {
  const BlocksScreen({super.key});

  @override
  ConsumerState<BlocksScreen> createState() => _BlocksScreenState();
}

class _BlocksScreenState extends ConsumerState<BlocksScreen> {
  StreamSubscription<Map<String, dynamic>>? _blockingEventsSubscription;
  final _appLimitNativeService = AppLimitNativeService();

  @override
  void initState() {
    super.initState();
    _setupBlockingEventListener();
    _setupAppLimitEventListener();
    // Initialize permissions when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(permissionProvider.notifier).checkPermissions();
      _syncLimitsToNative();
    });
  }

  void _setupAppLimitEventListener() {
    _appLimitNativeService.initLimitEventsHandler((packageName) {
      print('⚠️ App limit reached for: $packageName');
      if (mounted) {
        _showAppLimitReachedDialog(packageName);
      }
    });
  }

  Future<void> _syncLimitsToNative() async {
    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) return;

      final appLimitsAsync = ref.read(appLimitsProvider(user.uid));
      appLimitsAsync.whenData((limits) async {
        final limitsMap = <String, int>{};
        for (final limit in limits) {
          if (limit.isActive) {
            limitsMap[limit.packageName] = limit.dailyLimit;
          }
        }
        await _appLimitNativeService.updateLimits(limitsMap);
        print('✅ Synced ${limitsMap.length} app limits to native');
      });
    } catch (e) {
      print('Error syncing limits to native: $e');
    }
  }

  void _showAppLimitReachedDialog(String packageName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Time Limit Reached',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You\'ve reached your daily time limit for this app.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              'Take a break and focus on your goals! 🎯',
              style: TextStyle(color: Color(0xFF82D65D), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(color: Color(0xFF82D65D), fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  void _setupBlockingEventListener() {
    try {
      final nativeService = ref.read(blocksNativeServiceProvider);
      _blockingEventsSubscription = nativeService.blockingEventsStream.listen(
        (event) => _handleBlockingEvent(event),
        onError: (error) => print('Blocking events stream error: $error'),
      );
    } catch (e) {
      print('Error setting up blocking event listener: $e');
    }
  }

  void _handleBlockingEvent(Map<String, dynamic> event) {
    try {
      final eventType = event['type'] as String?;

      if (eventType == 'website_blocked') {
        final url = event['url'] as String?;
        final appName = event['appName'] as String?;
        if (url != null && appName != null) {
          _showWebsiteBlockedSnackBar(url, appName);
        }
      }
    } catch (e) {
      print('Error handling blocking event: $e');
    }
  }

  void _showWebsiteBlockedSnackBar(String url, String appName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.block, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🚫 Website Blocked',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '$url in $appName',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  void dispose() {
    _blockingEventsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverAppBar(
              floating: true,
              pinned: true,
              title: const Text(
                'Blocks',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
            ),

            // Content
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 1. App Limits
                  _AppLimitsSection(userId: user.uid),
                  const SizedBox(height: 24),

                  // 2. Short Form Content
                  _ShortFormBlocksSection(userId: user.uid),
                  const SizedBox(height: 24),

                  // 3. Website Blocking
                  _WebsiteBlockingSection(userId: user.uid),
                  const SizedBox(height: 24),

                  // 4. Notifications
                  _NotificationBlockingSection(userId: user.uid),
                  const SizedBox(height: 100), // Bottom padding for scrolling
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 1. APP LIMITS SECTION
// ============================================================================

class _AppLimitsSection extends ConsumerWidget {
  final String userId;

  const _AppLimitsSection({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLimitsAsync = ref.watch(appLimitsProvider(userId));

    return _BlockSection(
      title: 'App Limits',
      icon: Icons.timer_outlined,
      description: 'Set daily usage limits for specific apps',
      child: appLimitsAsync.when(
        data: (limits) {
          if (limits.isEmpty) {
            return _EmptyState(
              icon: Icons.timer_off_outlined,
              message: 'No app limits set yet',
              actionLabel: 'Add Limit',
              onAction: () => _showAddAppLimitDialog(context),
            );
          }

          return Column(
            children: [
              ...limits.map(
                (limit) => _AppLimitTile(limit: limit, userId: userId),
              ),
              const SizedBox(height: 12),
              _AddButton(
                label: 'Add App Limit',
                onPressed: () => _showAddAppLimitDialog(context),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(message: 'Could not load limits'),
      ),
    );
  }

  void _showAddAppLimitDialog(BuildContext context) async {
    // Check usage stats permission first
    final hasUsagePermission = await _checkAndRequestUsageStatsPermission(
      context,
    );
    if (!hasUsagePermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Usage Access permission is required for app limits',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => const _AppSelectionDialog(),
    );
  }
}

class _AppLimitTile extends ConsumerStatefulWidget {
  final AppLimitModel limit;
  final String userId;

  const _AppLimitTile({required this.limit, required this.userId});

  @override
  ConsumerState<_AppLimitTile> createState() => _AppLimitTileState();
}

class _AppLimitTileState extends ConsumerState<_AppLimitTile> {
  int _currentUsage = 0;
  bool _isLoadingUsage = false;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _syncAllLimitsToNative() async {
    try {
      final appLimitsAsync = ref.read(appLimitsProvider(widget.userId));
      await appLimitsAsync.when(
        data: (limits) async {
          final limitsMap = <String, int>{};
          for (final limit in limits) {
            if (limit.isActive) {
              limitsMap[limit.packageName] = limit.dailyLimit;
            }
          }
          final nativeService = AppLimitNativeService();
          await nativeService.updateLimits(limitsMap);
          print('✅ Synced ${limitsMap.length} limits to native');
        },
        loading: () async {},
        error: (e, _) async {
          print('Error syncing limits: $e');
        },
      );
    } catch (e) {
      print('Error in _syncAllLimitsToNative: $e');
    }
  }

  Future<void> _loadUsage() async {
    if (!widget.limit.isActive) return;

    setState(() => _isLoadingUsage = true);
    try {
      final nativeService = AppLimitNativeService();
      final usage = await nativeService.getTodayUsage(widget.limit.packageName);
      if (mounted) {
        setState(() {
          _currentUsage = usage;
          _isLoadingUsage = false;
        });
      }
    } catch (e) {
      print('Error loading usage: $e');
      if (mounted) {
        setState(() => _isLoadingUsage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.limit.dailyLimit > 0
        ? (_currentUsage / widget.limit.dailyLimit).clamp(0.0, 1.0)
        : 0.0;
    final remainingMinutes = (widget.limit.dailyLimit - _currentUsage).clamp(
      0,
      widget.limit.dailyLimit,
    );
    final isNearLimit = progress >= 0.75;
    final isExceeded = progress >= 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExceeded
              ? Colors.red.withOpacity(0.3)
              : isNearLimit
              ? Colors.orange.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isExceeded
                    ? Colors.red.withOpacity(0.1)
                    : isNearLimit
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isExceeded ? Icons.block : Icons.timer,
                color: isExceeded
                    ? Colors.red
                    : isNearLimit
                    ? Colors.orange
                    : Colors.white70,
              ),
            ),
            title: Text(
              widget.limit.appName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: widget.limit.isActive
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        isExceeded
                            ? 'Limit exceeded'
                            : '$remainingMinutes min remaining',
                        style: TextStyle(
                          color: isExceeded
                              ? Colors.red
                              : isNearLimit
                              ? Colors.orange
                              : Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Inactive',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.limit.isActive) ...[
                  IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: Colors.white.withOpacity(0.4),
                      size: 20,
                    ),
                    onPressed: _isLoadingUsage ? null : _loadUsage,
                  ),
                ],
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: widget.limit.isActive,
                    activeThumbColor: const Color(0xFF82D65D),
                    activeTrackColor: const Color(0xFF82D65D).withOpacity(0.3),
                    inactiveTrackColor: Colors.grey.withOpacity(0.2),
                    onChanged: (value) => _handleToggle(value),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.more_vert,
                    color: Colors.white.withOpacity(0.4),
                  ),
                  onPressed: () => _showOptionsMenu(context),
                ),
              ],
            ),
          ),
          if (widget.limit.isActive) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$_currentUsage min',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${widget.limit.dailyLimit} min',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isExceeded
                            ? Colors.red
                            : isNearLimit
                            ? Colors.orange
                            : const Color(0xFF82D65D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleToggle(bool value) async {
    // If enabling, check permissions first
    if (value) {
      final hasPermission = await _checkAndRequestPermissions(context, ref);
      if (!hasPermission) return;
    }

    // If disabling, check parental control
    if (!value) {
      final parentalControlDoc = await FirebaseFirestore.instance
          .collection('parental_controls')
          .doc(widget.userId)
          .get();

      if (parentalControlDoc.exists) {
        final data = parentalControlDoc.data();
        final isEnabled = data?['isEnabled'] as bool? ?? false;

        if (isEnabled) {
          final verified = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => VerifyPasswordDialog(
              title: 'Parental Control',
              description: 'Enter PIN to disable app limit',
              onVerify: (password) async {
                final service = ref.read(parentalControlServiceProvider);
                return await service.verifyPassword(
                  userId: widget.userId,
                  password: password,
                );
              },
            ),
          );

          if (verified != true) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ Incorrect PIN or cancelled'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          }
        }
      }
    }

    try {
      // Update Firebase
      await ref
          .read(appLimitNotifierProvider.notifier)
          .toggleAppLimitStatus(widget.userId, widget.limit.packageName, value);

      // Sync all active limits to native
      await _syncAllLimitsToNative();

      if (value) {
        _loadUsage(); // Reload usage when enabling
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? '✅ ${widget.limit.appName} limit enabled'
                  : '🔓 ${widget.limit.appName} limit disabled',
            ),
            backgroundColor: const Color(0xFF1E1E1E),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error toggling limit: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update limit'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white70),
              title: const Text(
                'Edit Limit',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Remove Limit',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmRemove();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog() {
    final controller = TextEditingController(
      text: widget.limit.dailyLimit.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Edit ${widget.limit.appName}',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Daily limit (minutes)',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final newLimit = int.tryParse(controller.text);
              if (newLimit != null && newLimit > 0) {
                try {
                  final updatedLimit = widget.limit.copyWith(
                    dailyLimit: newLimit,
                  );

                  // Update Firebase
                  await ref
                      .read(appLimitNotifierProvider.notifier)
                      .updateAppLimit(widget.userId, updatedLimit);

                  // Sync all limits to native
                  await _syncAllLimitsToNative();

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Limit updated'),
                        backgroundColor: Color(0xFF1E1E1E),
                      ),
                    );
                  }
                } catch (e) {
                  print('Error updating limit: $e');
                }
              }
            },
            child: const Text(
              'Save',
              style: TextStyle(
                color: Color(0xFF82D65D),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemove() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Remove Limit?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove limit for ${widget.limit.appName}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              try {
                // Remove from Firebase
                await ref
                    .read(appLimitNotifierProvider.notifier)
                    .removeAppLimit(widget.userId, widget.limit.packageName);

                // Sync all limits to native (this will remove it)
                await _syncAllLimitsToNative();

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ ${widget.limit.appName} limit removed'),
                      backgroundColor: const Color(0xFF1E1E1E),
                    ),
                  );
                }
              } catch (e) {
                print('Error removing limit: $e');
              }
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. SHORT FORM BLOCKS SECTION
// ============================================================================

class _ShortFormBlocksSection extends ConsumerWidget {
  final String userId;

  const _ShortFormBlocksSection({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the blockedContentProvider directly and extract shortFormBlocks
    final contentAsync = ref.watch(blockedContentProvider(userId));

    return _BlockSection(
      title: 'Short Form Content',
      icon: Icons.video_library_outlined,
      description: 'Block addictive short-form feeds',
      child: contentAsync.when(
        data: (content) {
          // Extract blocks directly from the content model
          final blocks = content.shortFormBlocks;

          // Log what we got from Firestore
          print(
            '📱 ShortFormBlocksSection: Retrieved from Firestore - ${blocks.keys.toList()}',
          );
          blocks.forEach((key, block) {
            print('   - $key: isBlocked=${block.isBlocked}');
          });

          return Column(
            children: [
              _ShortFormToggle(
                title: 'YouTube Shorts',
                subtitle: 'Block Shorts shelf & feed',
                icon: Icons.play_circle_outline,
                isBlocked: blocks['YouTube_Shorts']?.isBlocked ?? false,
                onChanged: (value) => _updateBlock(
                  context,
                  ref,
                  userId,
                  'YouTube',
                  'Shorts',
                  value,
                ),
              ),
              _ShortFormToggle(
                title: 'Instagram Reels',
                subtitle: 'Block Reels tab & feed',
                icon: Icons.camera_alt_outlined,
                isBlocked: blocks['Instagram_Reels']?.isBlocked ?? false,
                onChanged: (value) => _updateBlock(
                  context,
                  ref,
                  userId,
                  'Instagram',
                  'Reels',
                  value,
                ),
              ),
              _ShortFormToggle(
                title: 'TikTok',
                subtitle: 'Block app entirely',
                icon: Icons.music_note_outlined,
                isBlocked: blocks['TikTok_Videos']?.isBlocked ?? false,
                onChanged: (value) => _updateBlock(
                  context,
                  ref,
                  userId,
                  'TikTok',
                  'Videos',
                  value,
                ),
              ),
              _ShortFormToggle(
                title: 'Facebook Reels',
                subtitle: 'Block Reels section',
                icon: Icons.facebook_outlined,
                isBlocked: blocks['Facebook_Reels']?.isBlocked ?? false,
                onChanged: (value) => _updateBlock(
                  context,
                  ref,
                  userId,
                  'Facebook',
                  'Reels',
                  value,
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, stack) =>
            _ErrorState(message: 'Could not load settings: $e'),
      ),
    );
  }

  Future<void> _updateBlock(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String platform,
    String feature,
    bool isBlocked,
  ) async {
    // If enabling, check permissions first
    if (isBlocked) {
      final hasPermissions = await _checkAndRequestPermissions(context, ref);
      if (!hasPermissions) {
        // Don't update if permissions not granted
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ Accessibility permission required to block content',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    // If disabling, check parental control
    if (!isBlocked) {
      print('🔐 Checking parental control for disabling $platform $feature');

      // Directly check Firestore for parental control
      final parentalControlDoc = await FirebaseFirestore.instance
          .collection('parental_controls')
          .doc(userId)
          .get();

      if (parentalControlDoc.exists) {
        final data = parentalControlDoc.data();
        final isEnabled = data?['isEnabled'] as bool? ?? false;
        print('🔐 Parental control found: isEnabled=$isEnabled');

        if (isEnabled) {
          print('🔐 Showing PIN dialog');
          // Show PIN verification dialog
          final verified = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => VerifyPasswordDialog(
              title: 'Parental Control',
              description: 'Enter PIN to disable $platform $feature blocking',
              onVerify: (password) async {
                final service = ref.read(parentalControlServiceProvider);
                return await service.verifyPassword(
                  userId: userId,
                  password: password,
                );
              },
            ),
          );

          print('🔐 PIN verification result: $verified');
          if (verified != true) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ Incorrect PIN or cancelled'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          }
        } else {
          print('🔐 Parental control is not enabled, allowing operation');
        }
      } else {
        print('🔐 No parental control document found, allowing operation');
      }
    }

    try {
      print('🔄 Updating $platform $feature to $isBlocked');

      // Update native service first
      final nativeService = ref.read(blocksNativeServiceProvider);
      await nativeService.setShortFormBlock(
        platform: platform,
        feature: feature,
        isBlocked: isBlocked,
      );
      print('✅ Native service updated for $platform $feature');

      // Then call the notifier method to update Firestore
      await ref
          .read(blockedContentNotifierProvider.notifier)
          .toggleShortFormBlockStatus(userId, platform, feature, isBlocked);

      print(
        '✅ Successfully updated $platform $feature to $isBlocked in Firestore',
      );

      // Show feedback to user
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isBlocked
                  ? '🚫 $platform $feature blocked'
                  : '✅ $platform $feature unblocked',
            ),
            backgroundColor: const Color(0xFF1E1E1E),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error updating short form block: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update $platform $feature'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

class _ShortFormToggle extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isBlocked;
  final ValueChanged<bool> onChanged;

  const _ShortFormToggle({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isBlocked,
    required this.onChanged,
  });

  @override
  State<_ShortFormToggle> createState() => _ShortFormToggleState();
}

class _ShortFormToggleState extends State<_ShortFormToggle> {
  bool? _optimisticValue;
  bool _isUpdating = false;
  DateTime? _lastUpdateTime;

  @override
  void didUpdateWidget(_ShortFormToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear optimistic value when Firestore confirms the change
    if (oldWidget.isBlocked != widget.isBlocked) {
      print(
        '🔄 Toggle ${widget.title}: Firestore updated from ${oldWidget.isBlocked} to ${widget.isBlocked}, optimistic was $_optimisticValue',
      );
      if (_optimisticValue != null && _optimisticValue == widget.isBlocked) {
        print(
          '✅ Toggle ${widget.title}: Clearing optimistic value (confirmed by Firestore)',
        );
        setState(() => _optimisticValue = null);
      } else if (_optimisticValue != null &&
          _optimisticValue != widget.isBlocked) {
        print(
          '⚠️ Toggle ${widget.title}: Firestore value conflicts with optimistic value',
        );
        // Firestore value is different from what we expected, trust Firestore
        setState(() => _optimisticValue = null);
      }
    }
  }

  void _revertOptimisticValue() {
    if (mounted) {
      setState(() {
        _optimisticValue = null;
        _isUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use optimistic value if available, otherwise use actual value
    final displayValue = _optimisticValue ?? widget.isBlocked;
    print(
      '🎨 Toggle ${widget.title}: Rendering with displayValue=$displayValue (optimistic=$_optimisticValue, firestore=${widget.isBlocked})',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Icon(
          widget.icon,
          color: displayValue ? const Color(0xFF82D65D) : Colors.grey,
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          widget.subtitle,
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
        value: displayValue,
        activeThumbColor: const Color(0xFF82D65D),
        activeTrackColor: const Color(0xFF82D65D).withOpacity(0.3),
        inactiveTrackColor: Colors.grey.withOpacity(0.2),
        onChanged: _isUpdating
            ? null
            : (value) {
                if (_isUpdating) return;

                // Set optimistic value immediately for instant UI feedback
                setState(() {
                  _optimisticValue = value;
                  _isUpdating = true;
                  _lastUpdateTime = DateTime.now();
                });

                // Call the actual update
                widget.onChanged(value);

                // Set a timeout to revert optimistic value if Firestore doesn't confirm
                Future.delayed(const Duration(seconds: 3)).then((_) {
                  if (mounted && _optimisticValue != null) {
                    // If optimistic value is still set after 3 seconds,
                    // it means the update failed (e.g., PIN was wrong)
                    if (widget.isBlocked != _optimisticValue) {
                      print(
                        '⚠️ Toggle ${widget.title}: Reverting optimistic value (update not confirmed)',
                      );
                      _revertOptimisticValue();
                    }
                  }
                });

                // Reset updating flag after shorter delay
                Future.delayed(const Duration(milliseconds: 800)).then((_) {
                  if (mounted) {
                    setState(() => _isUpdating = false);
                  }
                });
              },
      ),
    );
  }
}

// ============================================================================
// 3. WEBSITE BLOCKING SECTION
// ============================================================================

class _WebsiteBlockingSection extends ConsumerWidget {
  final String userId;

  const _WebsiteBlockingSection({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final websitesAsync = ref.watch(blockedWebsitesProvider(userId));

    return _BlockSection(
      title: 'Website Blocking',
      icon: Icons.language,
      description: 'Block distracting websites in browsers',
      child: websitesAsync.when(
        data: (websites) {
          if (websites.isEmpty) {
            return _EmptyState(
              icon: Icons.public_off,
              message: 'No websites blocked',
              actionLabel: 'Add Website',
              onAction: () => _showAddWebsiteDialog(context, ref),
            );
          }

          return Column(
            children: [
              ...websites.map(
                (website) => _WebsiteTile(website: website, userId: userId),
              ),
              const SizedBox(height: 12),
              _AddButton(
                label: 'Add Website',
                onPressed: () => _showAddWebsiteDialog(context, ref),
              ),
              const SizedBox(height: 8),
              _DiagnosticsButton(
                onPressed: () => _runWebsiteBlockingDiagnostics(context, ref),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(message: 'Could not load websites'),
      ),
    );
  }

  void _showAddWebsiteDialog(BuildContext context, WidgetRef ref) {
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Block Website',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Website Name',
                hintText: 'e.g. Facebook',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Website URL',
                hintText: 'e.g. facebook.com',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final url = urlController.text.trim();
              final name = nameController.text.trim();
              if (url.isNotEmpty && name.isNotEmpty) {
                // Check permissions first
                final hasPermission = await _checkAndRequestPermissions(
                  context,
                  ref,
                );
                if (!hasPermission) {
                  Navigator.pop(context);
                  return;
                }

                final nativeService = ref.read(blocksNativeServiceProvider);
                final website = BlockedWebsite(
                  url: url,
                  name: name,
                  isActive: true,
                );

                try {
                  // Add to native service first
                  await nativeService.addBlockedWebsite(
                    url: url,
                    name: name,
                    isActive: true,
                  );

                  // Then add to Firebase
                  await ref
                      .read(blockedContentNotifierProvider.notifier)
                      .addBlockedWebsite(userId, website);

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ $name blocked'),
                        backgroundColor: const Color(0xFF1E1E1E),
                      ),
                    );
                  }
                } catch (e) {
                  print('❌ Error adding blocked website: $e');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to block website'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text(
              'Block',
              style: TextStyle(
                color: Color(0xFF82D65D),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebsiteTile extends ConsumerWidget {
  final BlockedWebsite website;
  final String userId;

  const _WebsiteTile({required this.website, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        leading: const Icon(Icons.public_off, color: Colors.white70),
        title: Text(website.url, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          website.name,
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: website.isActive,
                activeThumbColor: const Color(0xFF82D65D),
                activeTrackColor: const Color(0xFF82D65D).withOpacity(0.3),
                inactiveTrackColor: Colors.grey.withOpacity(0.2),
                onChanged: (value) async {
                  // If enabling, check permissions first
                  if (value) {
                    final hasPermission = await _checkAndRequestPermissions(
                      context,
                      ref,
                    );
                    if (!hasPermission) {
                      return;
                    }
                  }

                  // If disabling, check parental control
                  if (!value) {
                    // Directly check Firestore for parental control
                    final parentalControlDoc = await FirebaseFirestore.instance
                        .collection('parental_controls')
                        .doc(userId)
                        .get();

                    if (parentalControlDoc.exists) {
                      final data = parentalControlDoc.data();
                      final isEnabled = data?['isEnabled'] as bool? ?? false;

                      if (isEnabled) {
                        final verified = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => VerifyPasswordDialog(
                            title: 'Parental Control',
                            description: 'Enter PIN to disable website block',
                            onVerify: (password) async {
                              final service = ref.read(
                                parentalControlServiceProvider,
                              );
                              return await service.verifyPassword(
                                userId: userId,
                                password: password,
                              );
                            },
                          ),
                        );

                        if (verified != true) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('❌ Incorrect PIN or cancelled'),
                                backgroundColor: Colors.red,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                          return;
                        }
                      }
                    }
                  }

                  final nativeService = ref.read(blocksNativeServiceProvider);

                  try {
                    // Update native service
                    await nativeService.addBlockedWebsite(
                      url: website.url,
                      name: website.name,
                      isActive: value,
                    );

                    // Update Firebase
                    await ref
                        .read(blockedContentNotifierProvider.notifier)
                        .toggleWebsiteBlockStatus(userId, website.url, value);
                  } catch (e) {
                    print('❌ Error toggling website: $e');
                  }
                },
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: Colors.white.withOpacity(0.4),
              ),
              onPressed: () async {
                final nativeService = ref.read(blocksNativeServiceProvider);

                try {
                  // Remove from native service
                  await nativeService.removeBlockedWebsite(website.url);

                  // Remove from Firebase
                  await ref
                      .read(blockedContentNotifierProvider.notifier)
                      .removeBlockedWebsite(userId, website.url);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ ${website.name} unblocked'),
                        backgroundColor: const Color(0xFF1E1E1E),
                      ),
                    );
                  }
                } catch (e) {
                  print('❌ Error removing website: $e');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 4. NOTIFICATION BLOCKING SECTION
// ============================================================================

class _NotificationBlockingSection extends ConsumerStatefulWidget {
  final String userId;

  const _NotificationBlockingSection({required this.userId});

  @override
  ConsumerState<_NotificationBlockingSection> createState() =>
      _NotificationBlockingSectionState();
}

class _NotificationBlockingSectionState
    extends ConsumerState<_NotificationBlockingSection> {
  // TODO: Move this state to a provider for persistence
  bool _blockAllNotifications = false;

  @override
  Widget build(BuildContext context) {
    return _BlockSection(
      title: 'Notifications',
      icon: Icons.notifications_off_outlined,
      description: 'Control notification access globally',
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              secondary: Icon(
                Icons.notifications_off,
                color: _blockAllNotifications
                    ? const Color(0xFF82D65D)
                    : Colors.grey,
              ),
              title: const Text(
                'Block All Notifications',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Silence all app notifications',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
              value: _blockAllNotifications,
              activeThumbColor: const Color(0xFF82D65D),
              activeTrackColor: const Color(0xFF82D65D).withOpacity(0.3),
              inactiveTrackColor: Colors.grey.withOpacity(0.2),
              onChanged: (value) {
                setState(() => _blockAllNotifications = value);
                // TODO: Save to backend via provider
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SHARED WIDGETS
// ============================================================================

class _BlockSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;
  final Widget child;
  const _BlockSection({
    required this.title,
    required this.icon,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF82D65D).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF82D65D), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

// Diagnostics button widget
class _DiagnosticsButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DiagnosticsButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF82D65D),
          side: const BorderSide(color: Color(0xFF82D65D)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.bug_report, size: 20),
        label: const Text('Run Diagnostics'),
      ),
    );
  }
}

// Website blocking diagnostics method
Future<void> _runWebsiteBlockingDiagnostics(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    final nativeService = ref.read(blocksNativeServiceProvider);

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Running diagnostics...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Get diagnostics
    final diagnostics = await nativeService.getWebsiteBlockingDiagnostics();
    final supportedBrowsers = await nativeService.getSupportedBrowsers();

    final result = StringBuffer();
    result.writeln('🔍 Website Blocking Diagnostics\n');

    // Service status
    final accessibilityEnabled =
        diagnostics['accessibilityServiceEnabled'] as bool? ?? false;
    final serviceRunning = diagnostics['serviceRunning'] as bool? ?? false;

    if (!accessibilityEnabled) {
      result.writeln('⚠️ Accessibility Service: DISABLED');
      result.writeln('   Website blocking requires accessibility service');
      result.writeln('');
      result.writeln('📋 Enable Steps:');
      result.writeln('1. Go to Android Settings');
      result.writeln('2. Accessibility > Pace');
      result.writeln('3. Toggle ON');
      result.writeln('');
    } else {
      result.writeln('✅ Accessibility Service: ENABLED');
      result.writeln('✅ Service Running: ${serviceRunning ? "YES" : "NO"}');
    }

    // Active blocked websites
    final activeWebsites = diagnostics['activeBlockedWebsites'] as List? ?? [];
    result.writeln('');
    result.writeln('🚫 Active Blocked Websites: ${activeWebsites.length}');
    if (activeWebsites.isNotEmpty) {
      for (var website in activeWebsites) {
        result.writeln('   • $website');
      }
    } else {
      result.writeln('   No websites currently blocked');
    }

    // Supported browsers
    result.writeln('');
    result.writeln('🌐 Installed Supported Browsers:');
    if (supportedBrowsers.isNotEmpty) {
      for (var browser in supportedBrowsers) {
        result.writeln('   ✓ $browser');
      }
    } else {
      result.writeln('   No supported browsers found');
    }

    // Testing instructions
    result.writeln('');
    result.writeln('🧪 Testing Instructions:');
    result.writeln('');
    result.writeln('1. Add a website to block (e.g., "facebook.com")');
    result.writeln('2. Open any supported browser');
    result.writeln('3. Navigate to the blocked website');
    result.writeln('4. You should see:');
    result.writeln('   • Blocking overlay appears');
    result.writeln('   • Browser navigates back automatically');
    result.writeln('');

    if (!accessibilityEnabled) {
      result.writeln('⚠️ Next Steps:');
      result.writeln('1. Enable Accessibility Service (see above)');
      result.writeln('2. Add websites to block');
      result.writeln('3. Test in any supported browser');
    } else if (activeWebsites.isEmpty) {
      result.writeln('💡 Next Steps:');
      result.writeln('1. Add websites to block above');
      result.writeln('2. Open a browser');
      result.writeln('3. Blocking should activate automatically');
    } else {
      result.writeln('✅ Ready to Test:');
      result.writeln('1. Open any supported browser');
      result.writeln('2. Try visiting a blocked website');
      result.writeln('3. Blocking should work automatically');
    }

    // Show results
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Diagnostics Report',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Text(
              result.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Close',
                style: TextStyle(color: Color(0xFF82D65D)),
              ),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    print('❌ Diagnostics error: $e');
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Error', style: TextStyle(color: Colors.white)),
          content: Text(
            'Failed to run diagnostics: $e',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(color: Color(0xFF82D65D)),
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _AddButton(label: actionLabel, onPressed: onAction),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Text(message, style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AddButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withOpacity(0.2)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.add, size: 20),
        label: Text(label),
      ),
    );
  }
}

// ============================================================================
// APP SELECTION DIALOG
// ============================================================================

class _AppSelectionDialog extends ConsumerStatefulWidget {
  const _AppSelectionDialog();

  @override
  ConsumerState<_AppSelectionDialog> createState() =>
      _AppSelectionDialogState();
}

class _AppSelectionDialogState extends ConsumerState<_AppSelectionDialog> {
  List<AppInfo> _installedApps = [];
  List<AppInfo> _filteredApps = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  Future<void> _syncAllLimitsToNative(String userId) async {
    try {
      final appLimitsAsync = ref.read(appLimitsProvider(userId));
      await appLimitsAsync.when(
        data: (limits) async {
          final limitsMap = <String, int>{};
          for (final limit in limits) {
            if (limit.isActive) {
              limitsMap[limit.packageName] = limit.dailyLimit;
            }
          }
          final nativeService = AppLimitNativeService();
          await nativeService.updateLimits(limitsMap);
          print('✅ Synced ${limitsMap.length} limits to native');
        },
        loading: () async {},
        error: (e, _) async {
          print('Error syncing limits: $e');
        },
      );
    } catch (e) {
      print('Error in _syncAllLimitsToNative: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadInstalledApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledApps() async {
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      if (mounted) {
        setState(() {
          _installedApps = apps;
          _filteredApps = apps;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading apps: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterApps(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredApps = _installedApps;
      } else {
        _filteredApps = _installedApps
            .where(
              (app) =>
                  app.name.toLowerCase().contains(query.toLowerCase()) ||
                  app.packageName.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select App',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search bar
            TextField(
              controller: _searchController,
              onChanged: _filterApps,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search apps...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.white.withOpacity(0.5),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // App list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredApps.isEmpty
                  ? Center(
                      child: Text(
                        'No apps found',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = _filteredApps[index];
                        return _AppListItem(
                          app: app,
                          onTap: () => _showLimitDialog(app),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLimitDialog(AppInfo app) {
    final limitController = TextEditingController(text: '60');
    String selectedAction = 'warn';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Set limit for ${app.name}',
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: limitController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Daily limit (minutes)',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Action on exceed:',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ...[
                ('warn', 'Warn', 'Show warning, can dismiss'),
                ('block', 'Block', 'Hard block, cannot dismiss'),
                ('notify', 'Notify', 'Notification only'),
              ].map(
                (option) => RadioListTile<String>(
                  value: option.$1,
                  groupValue: selectedAction,
                  onChanged: (value) {
                    setState(() => selectedAction = value!);
                  },
                  title: Text(
                    option.$2,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    option.$3,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                  activeColor: const Color(0xFF82D65D),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                final limit = int.tryParse(limitController.text);
                if (limit != null && limit > 0) {
                  await _addAppLimit(app, limit, selectedAction);
                  if (context.mounted) {
                    Navigator.pop(context); // Close limit dialog
                    Navigator.pop(context); // Close app selection dialog
                  }
                }
              },
              child: const Text(
                'Add Limit',
                style: TextStyle(
                  color: Color(0xFF82D65D),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAppLimit(
    AppInfo app,
    int limitMinutes,
    String action,
  ) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    // Check permissions first
    final hasPermission = await _checkAndRequestPermissions(context, ref);
    if (!hasPermission) return;

    try {
      final limit = AppLimitModel(
        packageName: app.packageName,
        appName: app.name,
        dailyLimit: limitMinutes,
        weeklyLimit: 0,
        isActive: true,
        actionOnExceed: action,
      );

      // Add to Firebase
      await ref
          .read(appLimitNotifierProvider.notifier)
          .addAppLimit(user.uid, limit);

      // Sync all limits to native
      await _syncAllLimitsToNative(user.uid);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Limit added for ${app.name}'),
            backgroundColor: const Color(0xFF1E1E1E),
          ),
        );
      }
    } catch (e) {
      print('Error adding limit: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add limit'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _AppListItem extends StatelessWidget {
  final AppInfo app;
  final VoidCallback onTap;

  const _AppListItem({required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: app.icon != null
            ? Image.memory(app.icon!, width: 40, height: 40)
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.android, color: Colors.white70),
              ),
        title: Text(app.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          app.packageName,
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.add_circle_outline,
          color: Colors.white.withOpacity(0.5),
        ),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================================
// APP LIMIT EXCEEDED OVERLAY
// ============================================================================

class AppLimitExceededOverlay extends StatelessWidget {
  final String appName;
  final int usedMinutes;
  final int limitMinutes;
  final bool canDismiss;

  const AppLimitExceededOverlay({
    super.key,
    required this.appName,
    required this.usedMinutes,
    required this.limitMinutes,
    this.canDismiss = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.block, size: 80, color: Colors.red),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Time Limit Reached',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'You\'ve used $usedMinutes minutes of $appName today.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Daily limit: $limitMinutes minutes',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 48),
                if (canDismiss)
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF82D65D),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'I Understand',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      const Icon(Icons.lock, color: Colors.red, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'This app is blocked for today',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
