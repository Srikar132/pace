import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pace/data/models/pomodoro_settings.dart';
import 'package:pace/data/models/user_settings_model.dart';

class SettingsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache settings in memory
  UserSettingsModel? _cachedSettings;
  String? _cachedUserId;

  Stream<UserSettingsModel?> streamSettings(String userId) {
    return _firestore
        .collection('userSettings')
        .doc(userId)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((doc) async {
          if (!doc.exists) {
            await _createDefaultSettings(userId);

            // Return default settings immediately while waiting for Firestore to sync
            final defaultSettings = UserSettingsModel(
              defaultDuration: 25,
              timerMode: 'timer',
              pomodoroSettings: PomodoroSettings.defaultSettings(),
              numberOfBreaks: 1,
              blockPhoneHomeScreen: false,
              strictMode: false,
              autoStartBreaks: true,
              soundEnabled: true,
              vibrationEnabled: true,
              theme: 'dark',
            );

            _cachedSettings = defaultSettings;
            _cachedUserId = userId;

            return defaultSettings;
          }

          final settings = UserSettingsModel.fromFirestore(doc);

          // Update memory cache
          _cachedSettings = settings;
          _cachedUserId = userId;

          return settings;
        });
  }

  UserSettingsModel? getCachedSettings(String userId) {
    if (_cachedUserId == userId) return _cachedSettings;
    return null;
  }

  // Method to ensure settings exist for user
  Future<UserSettingsModel> ensureSettingsExist(String userId) async {
    try {
      final doc = await _firestore.collection('userSettings').doc(userId).get();

      if (doc.exists) {
        final settings = UserSettingsModel.fromFirestore(doc);
        _cachedSettings = settings;
        _cachedUserId = userId;
        return settings;
      } else {
        // Create default settings
        final defaultSettings = UserSettingsModel(
          defaultDuration: 25,
          timerMode: 'timer',
          pomodoroSettings: PomodoroSettings.defaultSettings(),
          numberOfBreaks: 1,
          blockPhoneHomeScreen: false,
          strictMode: false,
          autoStartBreaks: true,
          soundEnabled: true,
          vibrationEnabled: true,
          theme: 'dark',
        );

        await _firestore
            .collection('userSettings')
            .doc(userId)
            .set(defaultSettings.toFirestore());

        _cachedSettings = defaultSettings;
        _cachedUserId = userId;

        return defaultSettings;
      }
    } catch (e) {
      debugPrint('Error ensuring settings exist: $e');
      rethrow;
    }
  }

  Future<void> updateSettings(String userId, UserSettingsModel settings) async {
    try {
      await _firestore
          .collection('userSettings')
          .doc(userId)
          .set(settings.toFirestore(), SetOptions(merge: true));

      // Update local cache immediately for UI responsiveness
      _cachedSettings = settings;
      _cachedUserId = userId;
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        debugPrint(
          'Offline: Settings saved locally and will sync when online.',
        );
        _cachedSettings = settings;
      } else {
        rethrow;
      }
    } catch (e) {
      debugPrint('Error updating settings: $e');
      rethrow;
    }
  }

  Future<void> _createDefaultSettings(String userId) async {
    final defaultSettings = UserSettingsModel(
      defaultDuration: 25,
      timerMode: 'timer',
      pomodoroSettings: PomodoroSettings.defaultSettings(),
      numberOfBreaks: 1,
      blockPhoneHomeScreen: false,
      strictMode: false,
      autoStartBreaks: true,
      soundEnabled: true,
      vibrationEnabled: true,
      theme: 'dark',
    );

    try {
      await _firestore
          .collection('userSettings')
          .doc(userId)
          .set(defaultSettings.toFirestore());
    } catch (e) {
      debugPrint("Error creating default settings: $e");
    }
  }
}
