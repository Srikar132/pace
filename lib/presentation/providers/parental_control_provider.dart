import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/models/parental_control.dart';

/// Provider for parental control settings
final parentalControlProvider = StreamProvider.family<ParentalControl, String>((
  ref,
  userId,
) {
  return FirebaseFirestore.instance
      .collection('parental_controls')
      .doc(userId)
      .snapshots()
      .map((doc) => ParentalControl.fromFirestore(doc));
});

/// Service class for parental control operations
class ParentalControlService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Hash password using SHA-256
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Create or update parental control with password
  Future<void> setupParentalControl({
    required String userId,
    required String password,
  }) async {
    final hashedPassword = _hashPassword(password);

    await _firestore.collection('parental_controls').doc(userId).set({
      'isEnabled': true,
      'passwordHash': hashedPassword,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'blockedApps': [],
      'blockedWebsites': [],
      'blockYoutubeShorts': false,
      'blockInstagramReels': false,
    }, SetOptions(merge: true));
  }

  /// Verify password
  Future<bool> verifyPassword({
    required String userId,
    required String password,
  }) async {
    try {
      final doc = await _firestore
          .collection('parental_controls')
          .doc(userId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      final storedHash = data?['passwordHash'] as String?;

      if (storedHash == null) return false;

      final inputHash = _hashPassword(password);
      return inputHash == storedHash;
    } catch (e) {
      return false;
    }
  }

  /// Enable parental mode
  Future<void> enableParentalMode(String userId) async {
    await _firestore.collection('parental_controls').doc(userId).update({
      'isEnabled': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Disable parental mode (requires password verification)
  Future<void> disableParentalMode(String userId) async {
    await _firestore.collection('parental_controls').doc(userId).update({
      'isEnabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Change password
  Future<void> changePassword({
    required String userId,
    required String newPassword,
  }) async {
    final hashedPassword = _hashPassword(newPassword);

    await _firestore.collection('parental_controls').doc(userId).update({
      'passwordHash': hashedPassword,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Check if parental control is enabled
  Future<bool> isParentalControlEnabled(String userId) async {
    try {
      final doc = await _firestore
          .collection('parental_controls')
          .doc(userId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      return data?['isEnabled'] ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Check if password is set
  Future<bool> hasPassword(String userId) async {
    try {
      final doc = await _firestore
          .collection('parental_controls')
          .doc(userId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      return data?['passwordHash'] != null;
    } catch (e) {
      return false;
    }
  }

  /// Add blocked app
  Future<void> addBlockedApp(String userId, String appPackage) async {
    await _firestore.collection('parental_controls').doc(userId).update({
      'blockedApps': FieldValue.arrayUnion([appPackage]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Remove blocked app
  Future<void> removeBlockedApp(String userId, String appPackage) async {
    await _firestore.collection('parental_controls').doc(userId).update({
      'blockedApps': FieldValue.arrayRemove([appPackage]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update content blocking settings
  Future<void> updateContentBlocking({
    required String userId,
    bool? blockYoutubeShorts,
    bool? blockInstagramReels,
    bool? blockWebsites,
    bool? blockAppCategories,
  }) async {
    final Map<String, dynamic> updates = {
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (blockYoutubeShorts != null) {
      updates['blockYoutubeShorts'] = blockYoutubeShorts;
    }
    if (blockInstagramReels != null) {
      updates['blockInstagramReels'] = blockInstagramReels;
    }
    if (blockWebsites != null) {
      updates['blockWebsites'] = blockWebsites;
    }
    if (blockAppCategories != null) {
      updates['blockAppCategories'] = blockAppCategories;
    }

    await _firestore
        .collection('parental_controls')
        .doc(userId)
        .update(updates);
  }
}

/// Provider for parental control service
final parentalControlServiceProvider = Provider<ParentalControlService>((ref) {
  return ParentalControlService();
});
