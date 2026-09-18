import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/presentation/providers/focus_session_provider.dart';
import 'package:pace/presentation/providers/permission_provider.dart';
import 'package:pace/services/native_service.dart';

/// One-shot app-launch bootstrap:
/// - checks whether a focus session was already running natively (e.g. the
///   app process was killed mid-session) and syncs it into
///   [focusSessionProvider]
/// - runs the initial permission sweep
/// before routing decisions are made.
///
/// This used to live in `SplashScreen`'s `initState()`/local `State` flags
/// (session sync) and a one-shot flag inside `build()` (permission sweep).
/// Moved into a provider so the router's `redirect` callback (a pure
/// function, no widget lifecycle) can depend on it directly, and so
/// `redirect` never has to judge `permissionState.allGranted` before the
/// real sweep has actually run - by the time `appBootstrapProvider` stops
/// loading, `PermissionState.hasCheckedOnce` is guaranteed true.
final appBootstrapProvider = FutureProvider<void>((ref) async {
  // Brief delay to let providers finish their own initial setup first.
  await Future.delayed(const Duration(milliseconds: 100));

  await Future.wait([
    _syncActiveSession(ref),
    ref.read(permissionProvider.notifier).checkPermissions(),
  ]);
});

Future<void> _syncActiveSession(Ref ref) async {
  final status = await NativeService.getCurrentSessionStatus();
  if (status != null && status['isActive'] == true) {
    await ref.read(focusSessionProvider.notifier).refreshSessionFromNative();
  }
}
