import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pace/core/router/app_router.dart';
import 'package:pace/presentation/providers/permission_provider.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/widgets/permission_instruction_dialog.dart';
import 'package:pace/models/model_manager.dart';

class PermissionScreen extends ConsumerStatefulWidget {
  const PermissionScreen({super.key});

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Add lifecycle observer to detect when user returns from settings
    WidgetsBinding.instance.addObserver(this);

    // Initial permission check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(permissionProvider.notifier).checkPermissions();
      }
    });
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app returns to foreground, recheck all permissions with a delay
    if (state == AppLifecycleState.resumed && mounted) {
      // Add a delay to ensure the app is fully resumed before checking
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          ref.read(permissionProvider.notifier).checkPermissions();
        }
      });
    }
  }

  Future<void> _showPermissionInstructionDialog({
    required String title,
    required String description,
    required List<String> steps,
    required String permissionType,
    required VoidCallback onRequestPermission,
  }) async {
    await BottomSheetManager.show(
      context: context,
      child: PermissionInstructionDialog(
        title: title,
        description: description,
        steps: steps,
        onAllowPressed: () async {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
          onRequestPermission();

          // Show confirmation dialog after user returns
          if (mounted) {
            await Future.delayed(const Duration(milliseconds: 1000));
            if (mounted) {
              await _showPermissionConfirmationDialog(permissionType);
            }
          }
        },
        allowButtonText: 'Open Settings',
      ),
    );
  }

  Future<void> _showPermissionConfirmationDialog(String permissionType) async {
    if (!mounted) return;

    final permissionNotifier = ref.read(permissionProvider.notifier);
    String permissionName = permissionType == 'overlay'
        ? 'Display Over Other Apps'
        : 'Display Popup Windows';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Enabled?'),
        content: Text(
          'Have you enabled the $permissionName permission? We\'ll check if it\'s working now.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
              }
              await Future.delayed(const Duration(milliseconds: 500));
              if (mounted) {
                await permissionNotifier.checkPermissions();
              }
            },
            child: const Text('Yes, I enabled it'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAllPermissionsConfirmationDialog() async {
    if (!mounted) return;

    final authState = ref.read(authStateProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm All Permissions'),
        content: const Text(
          'Have you granted all the required permissions? This will complete your setup.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
              }

              // Recheck permissions first
              await ref.read(permissionProvider.notifier).checkPermissions();

              // Wait a bit for state to update
              await Future.delayed(const Duration(milliseconds: 300));

              if (!mounted) return;

              final updatedPermissionState = ref.read(permissionProvider);

              debugPrint('Updated Permission State: $updatedPermissionState');

              // Check if all permissions are granted
              if (updatedPermissionState.allGranted) {
                // Complete permissions
                await authState.when(
                  data: (user) async {
                    if (user != null) {
                      try {
                        await ref
                            .read(permissionProvider.notifier)
                            .completePermissions(user.uid);

                        // Route back through /splash so the router's
                        // redirect logic (single source of truth) decides
                        // where to actually land, instead of duplicating
                        // that decision here.
                        if (!context.mounted) return;

                        context.go(splashRoute);
                      } catch (e) {
                        if (mounted) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: theme.colorScheme.error,
                            ),
                          );
                        }
                      }
                    }
                  },
                  loading: () {},
                  error: (error, stack) {},
                );
              } else {
                // Show error - not all permissions granted
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please grant all permissions before continuing. Missing: ${_getMissingPermissions(updatedPermissionState)}',
                      ),
                      backgroundColor: theme.colorScheme.error,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            child: const Text('Yes, Complete Setup'),
          ),
        ],
      ),
    );
  }

  String _getMissingPermissions(PermissionState state) {
    final missing = <String>[];
    if (!state.usagePermission) missing.add('Usage Stats');
    if (!state.backgroundPermission) missing.add('Background');
    if (!state.overlayPermission) missing.add('Overlay');
    if (!state.displayPopupPermission) missing.add('Display Popup');
    if (!state.accessibilityPermission) missing.add('Accessibility');
    return missing.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissionState = ref.watch(permissionProvider);
    final permissionNotifier = ref.read(permissionProvider.notifier);
    debugPrint('Permission State Changed: $permissionState');

    // Listen for permission changes but DO NOT auto-navigate
    // User must manually confirm completion via the button
    ref.listen(permissionProvider, (previous, current) {
      if (!mounted) return;

      // Log permission status for debugging
      debugPrint('Permissions updated - All granted: ${current.allGranted}');
      debugPrint('  Usage: ${current.usagePermission}');
      debugPrint('  Background: ${current.backgroundPermission}');
      debugPrint('  Overlay: ${current.overlayPermission}');
      debugPrint('  Display Popup: ${current.displayPopupPermission}');
      debugPrint('  Accessibility: ${current.accessibilityPermission}');
      debugPrint('  Notification: ${current.notificationPermission}');
    });

    final permissions = [
      {
        'title': 'Usage permission',
        'description': 'This allows us to track your app usage.',
        'granted': permissionState.usagePermission,
        'onTap': () async {
          await permissionNotifier.requestUsagePermission();
          // Recheck after a short delay to allow settings to update
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            await permissionNotifier.checkPermissions();
          }
        },
      },
      {
        'title': 'Background permission',
        'description':
            'Keep the app running in the background for continuous monitoring.',
        'granted': permissionState.backgroundPermission,
        'onTap': () async {
          await permissionNotifier.requestBackgroundPermission();
          // Recheck after a short delay
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            await permissionNotifier.checkPermissions();
          }
        },
      },
      {
        'title': 'Notification permission',
        'description': 'Allow the app to send you notifications.',
        'granted': permissionState.notificationPermission,
        'onTap': () async {
          await permissionNotifier.requestNotificationPermission();
          // Recheck after a short delay
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            await permissionNotifier.checkPermissions();
          }
        },
      },
      {
        'title': 'Display over other apps',
        'description': 'Show blocking screens when you open distracting apps.',
        'granted': permissionState.overlayPermission,
        'onTap': () => _showPermissionInstructionDialog(
          title: 'Display Over Other Apps Permission',
          description:
              'This permission allows Pace to display blocking screens over other apps when you try to open distracting apps.',
          steps: const [
            'Tap "Open Settings" below',
            'Find "Pace" in the app list',
            'Toggle "Allow display over other apps" ON',
            'Return to this app',
          ],
          permissionType: 'overlay',
          onRequestPermission: permissionNotifier.requestOverlayPermission,
        ),
      },
      {
        'title': 'Display pop up permission',
        'description': 'Show focus reminders and motivational popups.',
        'granted': permissionState.displayPopupPermission,
        'onTap': () => _showPermissionInstructionDialog(
          title: 'Display Popup Windows Permission',
          description:
              'This permission allows Pace to show popup reminders and motivational messages to help you stay focused.',
          steps: const [
            'Tap "Open Settings" below',
            'Find "Pace" in the Special App Access list',
            'Look for "Display pop-up windows" or similar option',
            'Toggle the permission ON',
            'Return to this app',
          ],
          permissionType: 'displayPopup',
          onRequestPermission: permissionNotifier.requestDisplayPopupPermission,
        ),
      },
      {
        'title': 'Accessibility Permission',
        'description': 'Enable advanced app blocking capabilities.',
        'granted': permissionState.accessibilityPermission,
        'onTap': () async {
          await permissionNotifier.requestAccessibilityPermission();
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            await permissionNotifier.checkPermissions();
          }
        },
      },
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Progress bar at top
              Container(
                width: double.infinity,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Mascot + Message
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.outline,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/mascot.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                            child: Icon(
                              Icons.android,
                              size: 30,
                              color: theme.colorScheme.primary,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.titleMedium,
                          children: [
                            const TextSpan(
                              text:
                                  'Almost there, allow these\npermissions to ',
                            ),
                            TextSpan(
                              text: 'focus\nalongside 9566 people\nnow! ',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // // Debug Card - Permission Status
              // Container(
              //   margin: const EdgeInsets.only(bottom: 16),
              //   padding: const EdgeInsets.all(16),
              //   decoration: BoxDecoration(
              //     color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              //     borderRadius: BorderRadius.circular(12),
              //     border: Border.all(
              //       color: theme.colorScheme.error.withValues(alpha: 0.5),
              //       width: 1,
              //     ),
              //   ),
              //   child: Column(
              //     crossAxisAlignment: CrossAxisAlignment.start,
              //     children: [
              //       Row(
              //         children: [
              //           Icon(
              //             Icons.bug_report,
              //             color: theme.colorScheme.error,
              //             size: 20,
              //           ),
              //           const SizedBox(width: 8),
              //           Text(
              //             'DEBUG: Permission Status',
              //             style: theme.textTheme.titleSmall?.copyWith(
              //               color: theme.colorScheme.error,
              //               fontWeight: FontWeight.bold,
              //             ),
              //           ),
              //         ],
              //       ),
              //       const SizedBox(height: 12),
              //       _buildDebugPermissionRow(
              //         'Usage Stats',
              //         permissionState.usagePermission,
              //         theme,
              //       ),
              //       _buildDebugPermissionRow(
              //         'Accessibility',
              //         permissionState.accessibilityPermission,
              //         theme,
              //       ),
              //       _buildDebugPermissionRow(
              //         'Background',
              //         permissionState.backgroundPermission,
              //         theme,
              //       ),
              //       _buildDebugPermissionRow(
              //         'Overlay',
              //         permissionState.overlayPermission,
              //         theme,
              //       ),
              //       _buildDebugPermissionRow(
              //         'Display Popup',
              //         permissionState.displayPopupPermission,
              //         theme,
              //       ),
              //       _buildDebugPermissionRow(
              //         'Notification',
              //         permissionState.notificationPermission,
              //         theme,
              //       ),
              //       const SizedBox(height: 8),
              //       Container(
              //         padding: const EdgeInsets.symmetric(
              //           horizontal: 8,
              //           vertical: 4,
              //         ),
              //         decoration: BoxDecoration(
              //           color: permissionState.allGranted
              //               ? Colors.green.withValues(alpha: 0.2)
              //               : Colors.orange.withValues(alpha: 0.2),
              //           borderRadius: BorderRadius.circular(6),
              //         ),
              //         child: Text(
              //           'All Granted: ${permissionState.allGranted ? "✅ YES" : "❌ NO"}',
              //           style: theme.textTheme.bodySmall?.copyWith(
              //             fontWeight: FontWeight.bold,
              //             color: permissionState.allGranted
              //                 ? Colors.green
              //                 : Colors.orange,
              //           ),
              //         ),
              //       ),
              //     ],
              //   ),
              // ),

              // Permission list
              Expanded(
                child: ListView.builder(
                  itemCount: permissions.length,
                  itemBuilder: (context, index) {
                    final permission = permissions[index];
                    return _PermissionTile(
                      title: permission['title'] as String,
                      description: permission['description'] as String,
                      granted: permission['granted'] as bool,
                      onTap: permission['onTap'] as Future<void> Function(),
                      isFirst: index == 0,
                    );
                  },
                ),
              ),

              Column(
                children: [
                  const SizedBox(height: 8),

                  // Info button
                  GestureDetector(
                    onTap: () {
                      _showPermissionInfoDialog(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.question_mark,
                              color: Colors.black,
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Why should I give this permission?',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: theme.textTheme.bodyMedium?.color,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Trust badge
                  Text(
                    'Trusted by 2M+ students ❤️',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // Complete Setup Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _showAllPermissionsConfirmationDialog();
                      },
                      child: const Text('Complete Setup'),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget _buildDebugPermissionRow(String name, bool granted, ThemeData theme) {
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(vertical: 2),
  //     child: Row(
  //       children: [
  //         Container(
  //           width: 16,
  //           height: 16,
  //           decoration: BoxDecoration(
  //             color: granted ? Colors.green : Colors.red,
  //             borderRadius: BorderRadius.circular(8),
  //           ),
  //           child: Icon(
  //             granted ? Icons.check : Icons.close,
  //             size: 12,
  //             color: Colors.white,
  //           ),
  //         ),
  //         const SizedBox(width: 8),
  //         Expanded(
  //           child: Text(
  //             name,
  //             style: theme.textTheme.bodySmall?.copyWith(
  //               fontWeight: FontWeight.w500,
  //               color: granted ? Colors.green.shade700 : Colors.red.shade700,
  //             ),
  //           ),
  //         ),
  //         Text(
  //           granted ? 'GRANTED' : 'DENIED',
  //           style: theme.textTheme.bodySmall?.copyWith(
  //             fontWeight: FontWeight.bold,
  //             fontSize: 10,
  //             color: granted ? Colors.green.shade700 : Colors.red.shade700,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }
}

class _PermissionTile extends StatefulWidget {
  final String title;
  final String description;
  final bool granted;
  final Future<void> Function() onTap;
  final bool isFirst;

  const _PermissionTile({
    required this.title,
    required this.description,
    required this.granted,
    required this.onTap,
    this.isFirst = false,
  });

  @override
  State<_PermissionTile> createState() => _PermissionTileState();
}

class _PermissionTileState extends State<_PermissionTile> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: widget.granted
                        ? theme.textTheme.bodySmall?.color
                        : null,
                    decoration: widget.granted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (widget.isFirst && !widget.granted) ...[
                  const SizedBox(height: 2),
                  Text(widget.description, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (!widget.granted)
            _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: GestureDetector(
                      onTap: () async {
                        if (mounted) {
                          setState(() => _isLoading = true);
                        }
                        try {
                          await widget.onTap();
                        } finally {
                          if (mounted) {
                            setState(() => _isLoading = false);
                          }
                        }
                      },
                      child: Text(
                        'Allow',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}

void _showPermissionInfoDialog(BuildContext context) {
  final theme = Theme.of(context);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Why these permissions?', style: theme.textTheme.titleLarge),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PermissionInfo(
              title: 'Usage Stats Permission',
              description:
                  'Helps us understand which apps distract you most, so we can block them during focus sessions.',
            ),
            const SizedBox(height: 12),
            _PermissionInfo(
              title: 'Display Over Other Apps',
              description:
                  'Allows us to show a blocking screen when you try to open distracting apps.',
            ),
            const SizedBox(height: 12),
            _PermissionInfo(
              title: 'Notification Permission',
              description:
                  'Sends you focus reminders and session completion notifications.',
            ),
            const SizedBox(height: 12),
            _PermissionInfo(
              title: 'Accessibility Permission',
              description:
                  'Enables advanced app blocking to help you stay focused.',
            ),
            const SizedBox(height: 12),
            _PermissionInfo(
              title: 'Background Permission',
              description:
                  'Keeps the app running in the background for continuous monitoring and blocking. This exempts the app from battery optimization.',
            ),
            const SizedBox(height: 12),
            _PermissionInfo(
              title: 'Display Popup Permission',
              description:
                  'Shows focus reminders and motivational popups to keep you on track.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _PermissionInfo extends StatelessWidget {
  final String title;
  final String description;

  const _PermissionInfo({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 3),
        Text(description, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
