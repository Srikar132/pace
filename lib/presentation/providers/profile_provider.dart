import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/data/models/achievement_model.dart';
import 'package:pace/data/models/profile_stats_model.dart';
import 'package:pace/data/repositories/profile_repository.dart';

// Profile Repository Provider
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository();
});

// Profile Stats Stream Provider
final profileStatsProvider = StreamProvider.family<ProfileStatsModel, String>((
    ref,
    userId,
    ) {
  return ref.watch(profileRepositoryProvider).streamProfileStats(userId);
});

// Achievements Stream Provider
final achievementsProvider =
StreamProvider.family<List<AchievementModel>, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).streamAchievements(userId);
});

// Profile Actions Notifier
class ProfileActionsNotifier extends Notifier<AsyncValue<void>> {
  late ProfileRepository _repository;

  @override
  AsyncValue<void> build() {
    _repository = ref.read(profileRepositoryProvider);
    return const AsyncValue.data(null);
  }

  Future<void> incrementTimeSaved(String userId, int minutes) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.incrementTimeSaved(userId, minutes);

      // Check for achievement unlocks
      final stats = await _repository.streamProfileStats(userId).first;
      await _repository.checkAndUnlockAchievements(userId, stats);
    });
  }

  Future<void> incrementTimeFocused(String userId, int minutes) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.incrementTimeFocused(userId, minutes);

      // Check for achievement unlocks
      final stats = await _repository.streamProfileStats(userId).first;
      await _repository.checkAndUnlockAchievements(userId, stats);
    });
  }

  Future<void> incrementInvites(String userId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.incrementInvites(userId);

      // Check for achievement unlocks
      final stats = await _repository.streamProfileStats(userId).first;
      await _repository.checkAndUnlockAchievements(userId, stats);
    });
  }

  Future<void> updateStats(String userId, ProfileStatsModel stats) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.updateProfileStats(userId, stats);
      await _repository.checkAndUnlockAchievements(userId, stats);
    });
  }
}

final profileActionsProvider =
NotifierProvider<ProfileActionsNotifier, AsyncValue<void>>(() {
  return ProfileActionsNotifier();
});