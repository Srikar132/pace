import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pace/data/models/focus_session_model.dart';
import 'package:flutter/foundation.dart';

class FocusSessionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create new session (works offline!)
  Future<String> createSession(FocusSessionModel session) async {
    try {
      final docRef = _firestore
          .collection('focusSessions')
          .doc(session.sessionId);
      await docRef.set(session.toFirestore());

      return docRef.id; // Now this will be the timestamp ID
    } catch (e) {
      debugPrint('Error creating session: $e');
      rethrow;
    }
  }

  // Update session (works offline!)
  Future<void> updateSession(
    String sessionId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _firestore
          .collection('focusSessions')
          .doc(sessionId)
          .update(updates);
    } catch (e) {
      debugPrint('Error updating session: $e');
      rethrow;
    }
  }

  // Get today's sessions (cached by Firebase!)
  Stream<List<FocusSessionModel>> streamTodaySessions(String userId) {
    final today = DateTime.now();
    final dateString =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    return _firestore
        .collection('focusSessions')
        .where('userId', isEqualTo: userId)
        .where('date', isEqualTo: dateString)
        .orderBy('startTime', descending: true)
        .snapshots(includeMetadataChanges: true) // Offline support
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => FocusSessionModel.fromFirestore(doc))
              .toList(),
        );
  }

  // Get session history (with pagination)
  Future<List<FocusSessionModel>> getSessionHistory({
    required String userId,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _firestore
          .collection('focusSessions')
          .where('userId', isEqualTo: userId)
          .orderBy('startTime', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();

      return snapshot.docs
          .map((doc) => FocusSessionModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting session history: $e');
      return [];
    }
  }

  // Complete session and update stats atomically
  Future<void> completeSession({
    required String sessionId,
    required String userId,
    required int actualDuration,
    required double completionRate,
    required String date,
  }) async {
    try {
      final batch = _firestore.batch();

      // Update session
      final sessionRef = _firestore.collection('focusSessions').doc(sessionId);
      batch.update(sessionRef, {
        'endTime': FieldValue.serverTimestamp(),
        'actualDuration': actualDuration,
        'status': 'completed',
        'completionRate': completionRate,
      });

      // Update user stats atomically
      final userRef = _firestore.collection('users').doc(userId);
      batch.update(userRef, {
        'totalFocusTime': FieldValue.increment(actualDuration),
        'totalSessions': FieldValue.increment(1),
        'lastActiveDate': FieldValue.serverTimestamp(),
      });

      // Update daily stats
      final dailyStatsRef = _firestore
          .collection('dailyStats')
          .doc(userId)
          .collection('days')
          .doc(date);

      batch.set(dailyStatsRef, {
        'date': date,
        'totalFocusTime': FieldValue.increment(actualDuration),
        'totalSessions': FieldValue.increment(1),
        'completedSessions': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      debugPrint('Error completing session: $e');
      rethrow;
    }
  }

  // Delete a session doc (used when a session is discarded without saving)
  Future<void> deleteSession(String sessionId) async {
    try {
      await _firestore.collection('focusSessions').doc(sessionId).delete();
    } catch (e) {
      debugPrint('Error deleting session: $e');
      rethrow;
    }
  }
}
