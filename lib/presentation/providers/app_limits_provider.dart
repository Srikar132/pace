import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/data/models/app_limit_model.dart';
import 'package:pace/data/repositories/app_limit_repository.dart';

// ============================================================================
// REPOSITORY PROVIDER
// ============================================================================
final appLimitRepositoryProvider = Provider<AppLimitRepository>((ref) {
  return AppLimitRepository();
});

// ============================================================================
// STREAM PROVIDERS (Auto-cached by Firebase)
// ============================================================================

// Stream all app limits for a user
final appLimitsProvider = StreamProvider.family<List<AppLimitModel>, String>((
  ref,
  userId,
) {
  return ref.watch(appLimitRepositoryProvider).getAppLimitsStream(userId);
});

// Stream active app limits only
final activeAppLimitsProvider =
    StreamProvider.family<List<AppLimitModel>, String>((ref, userId) {
      return ref
          .watch(appLimitRepositoryProvider)
          .getActiveAppLimitsStream(userId);
    });

// Stream specific app limit
final specificAppLimitProvider =
    StreamProvider.family<
      AppLimitModel?,
      ({String userId, String packageName})
    >((ref, params) {
      return ref
          .watch(appLimitRepositoryProvider)
          .getAppLimitStream(params.userId, params.packageName);
    });

// ============================================================================
// FUTURE PROVIDERS
// ============================================================================

// Get all app limits (one-time fetch)
final fetchAppLimitsProvider =
    FutureProvider.family<List<AppLimitModel>, String>((ref, userId) async {
      return ref.watch(appLimitRepositoryProvider).getAppLimits(userId);
    });

// Get specific app limit (one-time fetch)
final fetchSpecificAppLimitProvider =
    FutureProvider.family<
      AppLimitModel?,
      ({String userId, String packageName})
    >((ref, params) async {
      return ref
          .watch(appLimitRepositoryProvider)
          .getAppLimit(params.userId, params.packageName);
    });

// ============================================================================
// STATE NOTIFIER FOR APP LIMIT OPERATIONS
// ============================================================================

class AppLimitNotifier extends Notifier<AsyncValue<void>> {
  late final AppLimitRepository _repository;

  @override
  AsyncValue<void> build() {
    _repository = ref.read(appLimitRepositoryProvider);
    return const AsyncValue.data(null);
  }

  // Add app limit (alias for setAppLimit for clarity)
  Future<void> addAppLimit(String userId, AppLimitModel appLimit) async {
    await setAppLimit(userId, appLimit);
  }

  // Set or update app limit
  Future<void> setAppLimit(String userId, AppLimitModel appLimit) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.setAppLimit(userId, appLimit);
      debugPrint('✅ App limit set for ${appLimit.packageName}');
    });
  }

  // Update entire app limit model
  Future<void> updateAppLimit(String userId, AppLimitModel appLimit) async {
    await setAppLimit(userId, appLimit);
  }

  // Update app limit fields
  Future<void> updateAppLimitFields(
    String userId,
    String packageName,
    Map<String, dynamic> updates,
  ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.updateAppLimit(userId, packageName, updates);
      debugPrint('✅ App limit updated for $packageName');
    });
  }

  // Remove app limit (alias for deleteAppLimit)
  Future<void> removeAppLimit(String userId, String packageName) async {
    await deleteAppLimit(userId, packageName);
  }

  // Delete app limit
  Future<void> deleteAppLimit(String userId, String packageName) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.deleteAppLimit(userId, packageName);
      debugPrint('✅ App limit deleted for $packageName');
    });
  }

  // Set multiple app limits at once
  Future<void> setMultipleAppLimits(
    String userId,
    List<AppLimitModel> appLimits,
  ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.setMultipleAppLimits(userId, appLimits);
      debugPrint('✅ ${appLimits.length} app limits set');
    });
  }

  // Toggle app limit active status
  Future<void> toggleAppLimitStatus(
    String userId,
    String packageName,
    bool isActive,
  ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.toggleAppLimitStatus(userId, packageName, isActive);
      debugPrint('✅ App limit status toggled for $packageName: $isActive');
    });
  }

  // Update daily limit
  Future<void> updateDailyLimit(
    String userId,
    String packageName,
    int dailyLimit,
  ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.updateDailyLimit(userId, packageName, dailyLimit);
      debugPrint('✅ Daily limit updated for $packageName: $dailyLimit min');
    });
  }

  // Update weekly limit
  Future<void> updateWeeklyLimit(
    String userId,
    String packageName,
    int weeklyLimit,
  ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.updateWeeklyLimit(userId, packageName, weeklyLimit);
      debugPrint('✅ Weekly limit updated for $packageName: $weeklyLimit min');
    });
  }

  // Update action on exceed
  Future<void> updateActionOnExceed(
    String userId,
    String packageName,
    String action,
  ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.updateActionOnExceed(userId, packageName, action);
      debugPrint('✅ Action on exceed updated for $packageName: $action');
    });
  }

  // Clear all app limits (for logout)
  Future<void> clearAllAppLimits(String userId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.clearAllAppLimits(userId);
      debugPrint('✅ All app limits cleared');
    });
  }
}

// Notifier Provider
final appLimitNotifierProvider =
    NotifierProvider<AppLimitNotifier, AsyncValue<void>>(() {
      return AppLimitNotifier();
    });

// ============================================================================
// DERIVED PROVIDERS (Computed values)
// ============================================================================

// Get count of active app limits
final activeAppLimitsCountProvider = Provider.family<int, String>((
  ref,
  userId,
) {
  final appLimitsAsync = ref.watch(activeAppLimitsProvider(userId));
  return appLimitsAsync.maybeWhen(
    data: (limits) => limits.length,
    orElse: () => 0,
  );
});

// Check if a specific app has a limit
final hasAppLimitProvider =
    Provider.family<bool, ({String userId, String packageName})>((ref, params) {
      final appLimitAsync = ref.watch(specificAppLimitProvider(params));
      return appLimitAsync.maybeWhen(
        data: (limit) => limit != null,
        orElse: () => false,
      );
    });

// Get all package names with limits
final appLimitPackageNamesProvider = Provider.family<List<String>, String>((
  ref,
  userId,
) {
  final appLimitsAsync = ref.watch(appLimitsProvider(userId));
  return appLimitsAsync.maybeWhen(
    data: (limits) => limits.map((l) => l.packageName).toList(),
    orElse: () => [],
  );
});
