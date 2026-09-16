import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pace/data/models/app_limit_model.dart';

class AppLimitRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection reference for app limits
  CollectionReference _getAppLimitsCollection(String userId) {
    return _firestore.collection('appLimits').doc(userId).collection('apps');
  }

  // Get all app limits for a user
  Future<List<AppLimitModel>> getAppLimits(String userId) async {
    try {
      final snapshot = await _getAppLimitsCollection(userId).get();

      return snapshot.docs
          .map((doc) => AppLimitModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting app limits: $e');
      rethrow;
    }
  }

  // Get app limits as a stream for real-time updates
  Stream<List<AppLimitModel>> getAppLimitsStream(String userId) {
    return _getAppLimitsCollection(userId)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppLimitModel.fromFirestore(doc))
              .toList(),
        );
  }

  // Get specific app limit
  Future<AppLimitModel?> getAppLimit(String userId, String packageName) async {
    try {
      final doc = await _getAppLimitsCollection(userId).doc(packageName).get();

      if (!doc.exists) return null;

      return AppLimitModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getting app limit for $packageName: $e');
      return null;
    }
  }

  // Get specific app limit as stream
  Stream<AppLimitModel?> getAppLimitStream(String userId, String packageName) {
    return _getAppLimitsCollection(userId)
        .doc(packageName)
        .snapshots(includeMetadataChanges: true)
        .map((doc) => doc.exists ? AppLimitModel.fromFirestore(doc) : null);
  }

  // Set or update app limit
  Future<void> setAppLimit(String userId, AppLimitModel appLimit) async {
    try {
      await _getAppLimitsCollection(userId)
          .doc(appLimit.packageName)
          .set(appLimit.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error setting app limit for ${appLimit.packageName}: $e');
      rethrow;
    }
  }

  // Update app limit fields
  Future<void> updateAppLimit(
    String userId,
    String packageName,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _getAppLimitsCollection(userId).doc(packageName).update(updates);
    } catch (e) {
      debugPrint('Error updating app limit for $packageName: $e');
      rethrow;
    }
  }

  // Delete app limit
  Future<void> deleteAppLimit(String userId, String packageName) async {
    try {
      await _getAppLimitsCollection(userId).doc(packageName).delete();
    } catch (e) {
      debugPrint('Error deleting app limit for $packageName: $e');
      rethrow;
    }
  }

  // Batch set multiple app limits
  Future<void> setMultipleAppLimits(
    String userId,
    List<AppLimitModel> appLimits,
  ) async {
    try {
      final batch = _firestore.batch();

      for (final appLimit in appLimits) {
        final docRef = _getAppLimitsCollection(
          userId,
        ).doc(appLimit.packageName);
        batch.set(docRef, appLimit.toFirestore(), SetOptions(merge: true));
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error setting multiple app limits: $e');
      rethrow;
    }
  }

  // Get active app limits only
  Future<List<AppLimitModel>> getActiveAppLimits(String userId) async {
    try {
      final snapshot = await _getAppLimitsCollection(
        userId,
      ).where('isActive', isEqualTo: true).get();

      return snapshot.docs
          .map((doc) => AppLimitModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting active app limits: $e');
      rethrow;
    }
  }

  // Get active app limits as stream
  Stream<List<AppLimitModel>> getActiveAppLimitsStream(String userId) {
    return _getAppLimitsCollection(userId)
        .where('isActive', isEqualTo: true)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppLimitModel.fromFirestore(doc))
              .toList(),
        );
  }

  // Toggle app limit active status
  Future<void> toggleAppLimitStatus(
    String userId,
    String packageName,
    bool isActive,
  ) async {
    try {
      await _getAppLimitsCollection(
        userId,
      ).doc(packageName).update({'isActive': isActive});
    } catch (e) {
      debugPrint('Error toggling app limit status for $packageName: $e');
      rethrow;
    }
  }

  // Update daily limit
  Future<void> updateDailyLimit(
    String userId,
    String packageName,
    int dailyLimit,
  ) async {
    try {
      await _getAppLimitsCollection(
        userId,
      ).doc(packageName).update({'dailyLimit': dailyLimit});
    } catch (e) {
      debugPrint('Error updating daily limit for $packageName: $e');
      rethrow;
    }
  }

  // Update weekly limit
  Future<void> updateWeeklyLimit(
    String userId,
    String packageName,
    int weeklyLimit,
  ) async {
    try {
      await _getAppLimitsCollection(
        userId,
      ).doc(packageName).update({'weeklyLimit': weeklyLimit});
    } catch (e) {
      debugPrint('Error updating weekly limit for $packageName: $e');
      rethrow;
    }
  }

  // Update action on exceed
  Future<void> updateActionOnExceed(
    String userId,
    String packageName,
    String action,
  ) async {
    try {
      await _getAppLimitsCollection(
        userId,
      ).doc(packageName).update({'actionOnExceed': action});
    } catch (e) {
      debugPrint('Error updating action on exceed for $packageName: $e');
      rethrow;
    }
  }

  // Clear all app limits for user (useful for logout)
  Future<void> clearAllAppLimits(String userId) async {
    try {
      final snapshot = await _getAppLimitsCollection(userId).get();
      final batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error clearing all app limits: $e');
      rethrow;
    }
  }
}