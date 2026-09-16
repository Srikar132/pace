import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pace/data/models/achievement_model.dart';
import 'package:pace/data/models/profile_stats_model.dart';

class ProfileRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get user profile stats stream
  Stream<ProfileStatsModel> streamProfileStats(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('stats')
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        // Create default stats if doesn't exist
        final defaultStats = ProfileStatsModel(userId: userId);
        _firestore
            .collection('users')
            .doc(userId)
            .collection('profile')
            .doc('stats')
            .set(defaultStats.toFirestore());
        return defaultStats;
      }
      return ProfileStatsModel.fromFirestore(snapshot);
    });
  }

  // Get user achievements stream
  Stream<List<AchievementModel>> streamAchievements(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('achievements')
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        // Initialize with default achievements
        final defaultAchievements =
        AchievementModel.getDefaultAchievements();
        final achievementsMap = {
          for (var achievement in defaultAchievements)
            achievement.id: achievement.toFirestore(),
        };
        _firestore
            .collection('users')
            .doc(userId)
            .collection('profile')
            .doc('achievements')
            .set({'achievements': achievementsMap});
        return defaultAchievements;
      }

      final data = snapshot.data();
      if (data == null || data['achievements'] == null) {
        return AchievementModel.getDefaultAchievements();
      }

      final achievementsMap = data['achievements'] as Map<String, dynamic>;
      return achievementsMap.values
          .map(
            (achievementData) => AchievementModel.fromFirestore(
          achievementData as Map<String, dynamic>,
        ),
      )
          .toList();
    });
  }

  // Update profile stats
  Future<void> updateProfileStats(
      String userId,
      ProfileStatsModel stats,
      ) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('stats')
        .set(stats.toFirestore(), SetOptions(merge: true));
  }

  // Update single achievement
  Future<void> updateAchievement(
      String userId,
      AchievementModel achievement,
      ) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('achievements')
        .set({
      'achievements.${achievement.id}': achievement.toFirestore(),
    }, SetOptions(merge: true));
  }

  // Increment time saved
  Future<void> incrementTimeSaved(String userId, int minutes) async {
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('stats');

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        transaction.set(docRef, {
          'userId': userId,
          'totalTimeSaved': minutes,
          'totalTimeFocused': 0,
          'totalInvites': 0,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else {
        final currentValue = snapshot.data()?['totalTimeSaved'] ?? 0;
        transaction.update(docRef, {
          'totalTimeSaved': currentValue + minutes,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // Increment time focused
  Future<void> incrementTimeFocused(String userId, int minutes) async {
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('stats');

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        transaction.set(docRef, {
          'userId': userId,
          'totalTimeSaved': 0,
          'totalTimeFocused': minutes,
          'totalInvites': 0,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else {
        final currentValue = snapshot.data()?['totalTimeFocused'] ?? 0;
        transaction.update(docRef, {
          'totalTimeFocused': currentValue + minutes,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // Increment invites
  Future<void> incrementInvites(String userId) async {
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('profile')
        .doc('stats');

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        transaction.set(docRef, {
          'userId': userId,
          'totalTimeSaved': 0,
          'totalTimeFocused': 0,
          'totalInvites': 1,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else {
        final currentValue = snapshot.data()?['totalInvites'] ?? 0;
        transaction.update(docRef, {
          'totalInvites': currentValue + 1,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // Check and unlock achievements based on stats
  Future<void> checkAndUnlockAchievements(
      String userId,
      ProfileStatsModel stats,
      ) async {
    final achievements = await streamAchievements(userId).first;

    for (var achievement in achievements) {
      if (!achievement.isUnlocked) {
        bool shouldUnlock = false;

        switch (achievement.type) {
          case AchievementType.timeSaved:
            shouldUnlock = stats.totalTimeSaved >= achievement.targetValue;
            break;
          case AchievementType.timeFocused:
            shouldUnlock = stats.totalTimeFocused >= achievement.targetValue;
            break;
          case AchievementType.inviteFriends:
            shouldUnlock = stats.totalInvites >= achievement.targetValue;
            break;
        }

        if (shouldUnlock) {
          final unlockedAchievement = achievement.copyWith(
            isUnlocked: true,
            unlockedAt: DateTime.now(),
          );
          await updateAchievement(userId, unlockedAchievement);
        }
      }
    }
  }
}