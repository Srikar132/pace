import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pace/data/models/user_model.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get user data from Firestore
  Future<UserModel?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) return null;

      return UserModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getting user data: $e');
      return null;
    }
  }

  // Update user onboarding status
  Future<void> updateOnboardingStatus(String uid, bool completed) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'hasCompletedOnboarding': completed,
      });
    } catch (e) {
      debugPrint('Error updating onboarding status: $e');
      rethrow;
    }
  }

  // Update permission status
  Future<void> updatePermissionStatus(String uid, bool granted) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'hasGrantedPermissions': granted,
      });
    } catch (e) {
      debugPrint('Error updating permission status: $e');
      rethrow;
    }
  }

  // Update onboarding answers
  Future<void> updateOnboardingAnswers({
    required String uid,
    String? procrastinationLevel,
    List<String>? distractions,
    String? preferredStudyTime,
  }) async {
    try {
      Map<String, dynamic>  updates = {};

      if (procrastinationLevel != null) {
        updates['procrastinationLevel'] = procrastinationLevel;
      }
      if (distractions != null) {
        updates['distractions'] = distractions;
      }

      if (preferredStudyTime != null) {
        updates['preferredStudyTime'] = preferredStudyTime;
      }

      await _firestore.collection('users').doc(uid).update(updates);
    } catch (e) {
      debugPrint('Error updating onboarding answers: $e');
      rethrow;
    }
  }

  // Stream user data
  Stream<UserModel?> streamUserData(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    });
  }

  Future<void> updateUserStatsAfterSession({
    required String userId,
    required int sessionDurationMinutes, // e.g., 25
    required int todayDurationMinutes, // Tracked locally
  }) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);

    // Convert minutes to milliseconds if your schema uses ms, or keep as minutes
    final sessionTimeToAdd = sessionDurationMinutes;

    try {
      await userRef.update({
        // 1. ATOMIC INCREMENTS (Safe & Fast)
        // This adds to the existing value, it doesn't overwrite it.
        'stats.totalFocusTime': FieldValue.increment(sessionTimeToAdd),
        'stats.totalSessions': FieldValue.increment(1),

        // 2. SIMPLE UPDATES
        'stats.lastActiveDate': FieldValue.serverTimestamp(),

        // 3. UPDATING "TODAY" STATS
        // Note: "Today" logic is tricky in DBs.
        // It's usually better to just set the new calculated value from the client
        // or handle the reset logic separately.
        'stats.todayFocusTime': FieldValue.increment(sessionTimeToAdd),
      });

      debugPrint("User stats updated successfully!");
    } catch (e) {
      debugPrint("Error updating stats: $e");
    }
  }

  Future<void> updateAppLimit(
    String userId,
    String packageName,
    int limitMinutes,
  ) async {
    // 1. Sanitize package name for Firestore keys (cannot contain dots if used directly,
    // but usually fine in map values. If used as a key, replace '.' with '_')
    try {
      final safeKey = packageName.replaceAll('.', '_');

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        // Update specifically the entry for this app inside the 'appLimits' map
        'appLimits.$safeKey': {
          'dailyLimit': limitMinutes,
          'actionOnExceed': 'block',
          'isActive': true,
        },
      });
    } catch (e) {
      debugPrint('Error updating app limit: $e');
      rethrow;
    }
  }
}
