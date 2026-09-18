import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/core/theme/app_theme.dart';
import 'package:pace/presentation/providers/blocked_content_provider.dart';
import 'package:pace/presentation/providers/app_management_provide.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/data/models/installed_app_model.dart';

class FocusTimerWidget extends ConsumerStatefulWidget {
  final String initialTimerMode;
  final int initialDefaultDuration;
  final VoidCallback onTap;

  const FocusTimerWidget({
    super.key,
    this.initialTimerMode = 'timer',
    this.initialDefaultDuration = 25,
    required this.onTap,
  });

  @override
  ConsumerState<FocusTimerWidget> createState() => _FocusTimerWidgetState();
}

class _FocusTimerWidgetState extends ConsumerState<FocusTimerWidget> {
  // Timer state
  late int _totalSeconds;
  late int _currentSeconds;

  @override
  void initState() {
    super.initState();
    _totalSeconds =
        widget.initialDefaultDuration * 60; // Convert minutes to seconds
    _currentSeconds = _totalSeconds;
  }

  @override
  void didUpdateWidget(FocusTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update timer when settings change
    if (oldWidget.initialDefaultDuration != widget.initialDefaultDuration) {
      setState(() {
        _totalSeconds = widget.initialDefaultDuration * 60;
        _currentSeconds = _totalSeconds;
      });
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final timerSize = screenWidth * 0.6; // 60% of screen width

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: timerSize,
        height: timerSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              spreadRadius: 5,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.cyan.withValues(alpha: 0.005),
              blurRadius: 20,
              spreadRadius: -5,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Circular progress indicator
            Positioned.fill(
              child: CircularProgressIndicator(
                value: _totalSeconds > 0 ? _currentSeconds / _totalSeconds : 0,
                strokeWidth: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),

            // Content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: timerSize * 0.05),
                  // Timer display
                  Text(
                    _formatTime(_currentSeconds),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: timerSize * 0.2,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                    ),
                  ),

                  SizedBox(height: timerSize * 0.04),

                  // Blocked apps indicator
                  _BlockedAppsIndicator(),

                  SizedBox(height: timerSize * 0.09),

                  // Edit button
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 12,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Edit',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// BLOCKED APPS INDICATOR WIDGET
// ============================================================================
class _BlockedAppsIndicator extends ConsumerWidget {
  const _BlockedAppsIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      data: (user) {
        if (user == null) {
          return const SizedBox();
        }

        final blockedAppsAsync = ref.watch(
          permanentlyBlockedAppsProvider(user.uid),
        );

        return blockedAppsAsync.when(
          data: (blockedPackages) {
            if (blockedPackages.isEmpty) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Text(
                  'No apps blocked',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }

            return _BlockedAppsPreview(
              blockedPackages: blockedPackages.toSet(),
            );
          },
          loading: () => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
          error: (_, _) => const SizedBox(),
        );
      },
      loading: () => const SizedBox(),
      error: (_, _) => const SizedBox(),
    );
  }
}

// ============================================================================
// BLOCKED APPS PREVIEW WIDGET
// ============================================================================
class _BlockedAppsPreview extends ConsumerWidget {
  final Set<String> blockedPackages;

  const _BlockedAppsPreview({required this.blockedPackages});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAppsAsync = ref.watch(installedAppsProvider);

    return allAppsAsync.when(
      data: (allApps) {
        final blockedAppsList = allApps
            .where((app) => blockedPackages.contains(app.packageName))
            .take(3)
            .toList();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (blockedAppsList.isNotEmpty) ...[
                _AppIconStack(apps: blockedAppsList),
                const SizedBox(width: 8),
              ],
              Text(
                '${blockedPackages.length} app${blockedPackages.length != 1 ? 's' : ''} blocked',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
      error: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Text(
          'Error loading apps',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// APP ICON STACK WIDGET
// ============================================================================
class _AppIconStack extends StatelessWidget {
  final List<InstalledApp> apps;
  static const double iconSize = 16.0;
  static const double overlap = 10.0;

  const _AppIconStack({required this.apps});

  @override
  Widget build(BuildContext context) {
    final displayApps = apps.take(3).toList();

    return SizedBox(
      height: iconSize,
      width: iconSize + ((displayApps.length - 1) * overlap),
      child: Stack(
        children: List.generate(displayApps.length, (index) {
          final app = displayApps[index];
          return Positioned(
            left: index * overlap,
            child: _AppIconCircle(packageName: app.packageName),
          );
        }),
      ),
    );
  }
}

// ============================================================================
// APP ICON CIRCLE WIDGET
// ============================================================================
class _AppIconCircle extends ConsumerWidget {
  final String packageName;
  static const double iconSize = 16.0;

  const _AppIconCircle({required this.packageName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconAsync = ref.watch(appIconProvider(packageName));

    return Container(
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
        color: AppColors.surfaceElevated,
      ),
      child: ClipOval(
        child: iconAsync.when(
          data: (iconBytes) {
            if (iconBytes != null) {
              return Image.memory(
                iconBytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              );
            }
            return const Icon(Icons.android, size: 8, color: Colors.white);
          },
          loading: () => const SizedBox(),
          error: (_, _) =>
              const Icon(Icons.android, size: 8, color: Colors.white),
        ),
      ),
    );
  }
}
