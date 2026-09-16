import 'package:pace/data/models/user_settings_model.dart';
import 'package:pace/data/repositories/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

// Stream provider with automatic caching
final userSettingsProvider = StreamProvider.family<UserSettingsModel?, String>((
  ref,
  userId,
) {
  return ref.watch(settingsRepositoryProvider).streamSettings(userId);
});

// Sync provider for instant access (no loading state)
final cachedSettingsProvider = Provider.family<UserSettingsModel?, String>((
  ref,
  userId,
) {
  return ref.watch(settingsRepositoryProvider).getCachedSettings(userId);
});

// Future provider to ensure settings exist and get them
final ensureSettingsProvider = FutureProvider.family<UserSettingsModel, String>(
  (ref, userId) async {
    return ref.watch(settingsRepositoryProvider).ensureSettingsExist(userId);
  },
);
