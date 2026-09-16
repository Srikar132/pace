import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/services/native_service.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/data/repositories/user_repository.dart';

// Permission state
class PermissionState {
  final bool usagePermission;
  final bool overlayPermission;
  final bool notificationPermission;
  final bool accessibilityPermission;
  final bool backgroundPermission;
  final bool displayPopupPermission;
  final bool isChecking;
  final bool isCompletingSetup;
  final bool hasCompletedSetup;

  PermissionState({
    this.usagePermission = false,
    this.overlayPermission = false,
    this.notificationPermission = false,
    this.accessibilityPermission = false,
    this.backgroundPermission = false,
    this.displayPopupPermission = false,
    this.isChecking = false,
    this.isCompletingSetup = false,
    this.hasCompletedSetup = false,
  });

  bool get allGranted =>
      usagePermission &&
      overlayPermission &&
      notificationPermission &&
      accessibilityPermission &&
      backgroundPermission;

  int get grantedCount {
    int count = 0;
    if (usagePermission) count++;
    if (overlayPermission) count++;
    if (notificationPermission) count++;
    if (accessibilityPermission) count++;
    if (backgroundPermission) count++;
    return count;
  }

  PermissionState copyWith({
    bool? usagePermission,
    bool? overlayPermission,
    bool? notificationPermission,
    bool? accessibilityPermission,
    bool? backgroundPermission,
    bool? displayPopupPermission,
    bool? isChecking,
    bool? isCompletingSetup,
    bool? hasCompletedSetup,
  }) {
    return PermissionState(
      usagePermission: usagePermission ?? this.usagePermission,
      overlayPermission: overlayPermission ?? this.overlayPermission,
      notificationPermission:
          notificationPermission ?? this.notificationPermission,
      accessibilityPermission:
          accessibilityPermission ?? this.accessibilityPermission,
      backgroundPermission: backgroundPermission ?? this.backgroundPermission,
      displayPopupPermission:
          displayPopupPermission ?? this.displayPopupPermission,
      isChecking: isChecking ?? this.isChecking,
      isCompletingSetup: isCompletingSetup ?? this.isCompletingSetup,
      hasCompletedSetup: hasCompletedSetup ?? this.hasCompletedSetup,
    );
  }
}

// Permission notifier
class PermissionNotifier extends Notifier<PermissionState> {
  late UserRepository _userRepository;
  DateTime? _lastCheckTime;
  static const _checkDebounceMs = 1000; // Minimum 1 second between checks

  @override
  PermissionState build() {
    _userRepository = ref.read(userRepositoryProvider);
    return PermissionState();
  }

  // Check all permissions with debounce to prevent infinite loops
  Future<void> checkPermissions() async {
    // Debounce: Skip if checked less than 1 second ago
    final now = DateTime.now();
    if (_lastCheckTime != null &&
        now.difference(_lastCheckTime!).inMilliseconds < _checkDebounceMs) {
      debugPrint('⏱️ Permission check skipped (debounced)');
      return;
    }

    _lastCheckTime = now;
    state = state.copyWith(isChecking: true);

    try {
      final usageGranted = await NativeService.hasUsageStatsPermission();
      final overlayGranted = await NativeService.hasOverlayPermission();
      final notificationGranted =
          await NativeService.hasNotificationPermission();
      final accessibilityGranted =
          await NativeService.hasAccessibilityPermission();
      final backgroundGranted = await NativeService.hasBackgroundPermission();
      final displayPopupGranted =
          await NativeService.hasDisplayPopupPermission();

      state = state.copyWith(
        usagePermission: usageGranted,
        overlayPermission: overlayGranted,
        notificationPermission: notificationGranted,
        accessibilityPermission: accessibilityGranted,
        backgroundPermission: backgroundGranted,
        displayPopupPermission: displayPopupGranted,
        isChecking: false,
      );
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      state = state.copyWith(isChecking: false);
    }
  }

  // Request usage permission
  Future<void> requestUsagePermission() async {
    await NativeService.requestUsageStatsPermission();
    // Don't check immediately - wait for user to return from settings
  }

  // Request overlay permission
  Future<void> requestOverlayPermission() async {
    await NativeService.requestOverlayPermission();
  }

  // Request Background permission
  Future<void> requestBackgroundPermission() async {
    await NativeService.requestBackgroundPermission();
  }

  // Request notification permission
  Future<void> requestNotificationPermission() async {
    await NativeService.requestNotificationPermission();
    // Check immediately for notification since it shows dialog
    await Future.delayed(const Duration(milliseconds: 500));
    final granted = await NativeService.hasNotificationPermission();
    state = state.copyWith(notificationPermission: granted);
  }

  // Request display popup permission (same as overlay)
  Future<void> requestDisplayPopupPermission() async {
    await NativeService.requestDisplayPopupPermission();
  }

  // Request accessibility permission
  Future<void> requestAccessibilityPermission() async {
    await NativeService.requestAccessibilityPermission();
  }

  // Complete permissions setup and navigate to SplashScreen
  Future<void> completePermissions(String userId) async {
    state = state.copyWith(isCompletingSetup: true);

    try {
      // Mark permissions as completed in local state only
      // No database dependency - permissions are checked in real-time via native service
      state = state.copyWith(isCompletingSetup: false, hasCompletedSetup: true);

      debugPrint(
        'Permissions completed successfully, navigating to SplashScreen',
      );
    } catch (e) {
      debugPrint('Error completing permissions: $e');
      state = state.copyWith(isCompletingSetup: false);
      rethrow;
    }
  }

  // Reset completion status (useful for testing or re-setup)
  void resetCompletion() {
    state = state.copyWith(hasCompletedSetup: false);
  }
}

// Permission provider
final permissionProvider =
    NotifierProvider<PermissionNotifier, PermissionState>(() {
      return PermissionNotifier();
    });
