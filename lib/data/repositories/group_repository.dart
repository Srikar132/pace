import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pace/data/models/group_memeber_model.dart';
import 'package:pace/data/models/group_model.dart';
import 'package:flutter/foundation.dart';

/// Repository handling all group-related database operations
class GroupRepository {
  final FirebaseFirestore _firestore;

  GroupRepository(this._firestore);

  // ==================== CREATE OPERATIONS ====================

  /// Creates a new group and adds the creator as the first member
  Future<String> createGroup({
    required String name,
    required String description,
    required String creatorId,
    required String creatorDisplayName,
    required GroupSettings settings,
  }) async {
    try {
      // Create group document
      final docRef = await _firestore.collection('groups').add({
        'name': name,
        'description': description,
        'creatorId': creatorId,
        'memberIds': [creatorId],
        'adminIds': [creatorId],
        'createdAt': FieldValue.serverTimestamp(),
        'totalFocusTime': 0,
        'memberFocusTime': {creatorId: 0},
        'settings': settings.toMap(),
      });

      // Add creator as first member in members subcollection
      await _firestore
          .collection('groups')
          .doc(docRef.id)
          .collection('members')
          .doc(creatorId)
          .set({
            'userId': creatorId,
            'groupId': docRef.id,
            'displayName': creatorDisplayName,
            'focusTime': 0,
            'joinedAt': FieldValue.serverTimestamp(),
            'isAdmin': true,
            'rank': 1,
          });

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create group: $e');
    }
  }

  // ==================== READ OPERATIONS ====================

  /// Get all groups where user is a member (real-time stream)
  Stream<List<GroupModel>> getUserGroups(String userId) {
    return _firestore
        .collection('groups')
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final groups = snapshot.docs
              .map((doc) => GroupModel.fromFirestore(doc))
              .toList();
          // Sort in memory instead of Firestore (no index needed)
          groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return groups;
        });
  }

  /// Get a specific group by ID (real-time stream)
  Stream<GroupModel?> getGroup(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map((doc) => doc.exists ? GroupModel.fromFirestore(doc) : null);
  }

  /// Get all members of a group (real-time stream, sorted by focus time)
  Stream<List<GroupMemberModel>> getGroupMembers(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .orderBy('focusTime', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupMemberModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// Search for public groups by name (real-time stream)
  Stream<List<GroupModel>> searchPublicGroups(String query) {
    return _firestore
        .collection('groups')
        .where('settings.isPublic', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupModel.fromFirestore(doc))
              .where(
                (group) =>
                    group.name.toLowerCase().contains(query.toLowerCase()),
              )
              .toList(),
        );
  }

  /// Get suggested public groups that user hasn't joined (real-time stream)
  Stream<List<GroupModel>> getSuggestedGroups(String userId) {
    return _firestore
        .collection('groups')
        .where('settings.isPublic', isEqualTo: true)
        .limit(10)
        .snapshots()
        .map((snapshot) {
          final allPublicGroups = snapshot.docs
              .map((doc) => GroupModel.fromFirestore(doc))
              .toList();

          // Filter out groups user is already a member of
          final suggestions = allPublicGroups
              .where((group) => !group.memberIds.contains(userId))
              .toList();

          // Sort by member count (popular first)
          suggestions.sort(
            (a, b) => b.memberIds.length.compareTo(a.memberIds.length),
          );

          return suggestions.take(5).toList(); // Show top 5 suggestions
        });
  }

  // ==================== UPDATE OPERATIONS ====================

  /// Join an existing group
  Future<void> joinGroup(
    String groupId,
    String userId,
    String displayName,
  ) async {
    try {
      final batch = _firestore.batch();

      // Add user to group's memberIds array
      final groupRef = _firestore.collection('groups').doc(groupId);
      batch.update(groupRef, {
        'memberIds': FieldValue.arrayUnion([userId]),
        'memberFocusTime.$userId': 0,
      });

      // Create member document in members subcollection
      final memberRef = groupRef.collection('members').doc(userId);
      batch.set(memberRef, {
        'userId': userId,
        'groupId': groupId,
        'displayName': displayName,
        'focusTime': 0,
        'joinedAt': FieldValue.serverTimestamp(),
        'isAdmin': false,
        'rank': 0,
      });

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to join group: $e');
    }
  }

  /// Update group focus time when user completes a focus session
  Future<void> updateGroupFocusTime(
    String groupId,
    String userId,
    int focusMinutes,
  ) async {
    try {
      final batch = _firestore.batch();

      // Update group's total focus time and member's contribution
      final groupRef = _firestore.collection('groups').doc(groupId);
      batch.update(groupRef, {
        'totalFocusTime': FieldValue.increment(focusMinutes),
        'memberFocusTime.$userId': FieldValue.increment(focusMinutes),
      });

      // Update member's individual focus time
      final memberRef = groupRef.collection('members').doc(userId);
      batch.update(memberRef, {
        'focusTime': FieldValue.increment(focusMinutes),
      });

      await batch.commit();

      // Update rankings asynchronously (doesn't block)
      _updateGroupRankings(groupId);
    } catch (e) {
      throw Exception('Failed to update group focus time: $e');
    }
  }

  /// Internal method to update member rankings based on focus time
  Future<void> _updateGroupRankings(String groupId) async {
    try {
      final membersSnapshot = await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .orderBy('focusTime', descending: true)
          .get();

      final batch = _firestore.batch();

      // Assign ranks based on sorted order
      for (var i = 0; i < membersSnapshot.docs.length; i++) {
        batch.update(membersSnapshot.docs[i].reference, {'rank': i + 1});
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Failed to update rankings: $e');
    }
  }

  // ==================== DELETE OPERATIONS ====================

  /// Leave a group (removes user from members)
  Future<void> leaveGroup(String groupId, String userId) async {
    try {
      final batch = _firestore.batch();

      // Remove user from group's arrays and focus time map
      final groupRef = _firestore.collection('groups').doc(groupId);
      batch.update(groupRef, {
        'memberIds': FieldValue.arrayRemove([userId]),
        'adminIds': FieldValue.arrayRemove([userId]),
        'memberFocusTime.$userId': FieldValue.delete(),
      });

      // Delete member document
      final memberRef = groupRef.collection('members').doc(userId);
      batch.delete(memberRef);

      await batch.commit();

      // Update rankings after member leaves
      _updateGroupRankings(groupId);
    } catch (e) {
      throw Exception('Failed to leave group: $e');
    }
  }

  /// Delete entire group (admin only)
  Future<void> deleteGroup(String groupId) async {
    try {
      // First, delete all members
      final membersSnapshot = await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .get();

      final batch = _firestore.batch();

      // Delete each member document
      for (var doc in membersSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // Delete the group document itself
      batch.delete(_firestore.collection('groups').doc(groupId));

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to delete group: $e');
    }
  }

  // ==================== UTILITY OPERATIONS ====================

  /// Check if user is a member of a group
  Future<bool> isMember(String groupId, String userId) async {
    try {
      final doc = await _firestore.collection('groups').doc(groupId).get();
      if (!doc.exists) return false;

      final memberIds = List<String>.from(doc.data()?['memberIds'] ?? []);
      return memberIds.contains(userId);
    } catch (e) {
      return false;
    }
  }

  /// Check if user is an admin of a group
  Future<bool> isAdmin(String groupId, String userId) async {
    try {
      final doc = await _firestore.collection('groups').doc(groupId).get();
      if (!doc.exists) return false;

      final adminIds = List<String>.from(doc.data()?['adminIds'] ?? []);
      return adminIds.contains(userId);
    } catch (e) {
      return false;
    }
  }
}
