import "package:cloud_firestore/cloud_firestore.dart";
import 'package:pace/data/models/group_memeber_model.dart';
import 'package:pace/data/models/group_model.dart';
import 'package:pace/data/repositories/group_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ==================== STREAM PROVIDERS ====================


/// Provider for GroupRepository
final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(FirebaseFirestore.instance);
});

/// Provides real-time list of groups where user is a member
final userGroupsProvider = StreamProvider.family<List<GroupModel>, String>((ref, userId) {
  final repository = ref.watch(groupRepositoryProvider);
  return repository.getUserGroups(userId);
});

/// Provides real-time data for a specific group
final groupProvider = StreamProvider.family<GroupModel?, String>((ref, groupId) {
  final repository = ref.watch(groupRepositoryProvider);
  return repository.getGroup(groupId);
});

/// Provides real-time list of members in a group (sorted by focus time)
final groupMembersProvider = StreamProvider.family<List<GroupMemberModel>, String>((ref, groupId) {
  final repository = ref.watch(groupRepositoryProvider);
  return repository.getGroupMembers(groupId);
});

/// Provides search results for public groups
final groupSearchProvider = StreamProvider.family<List<GroupModel>, String>((ref, query) {
  if (query.isEmpty) {
    return Stream.value([]);
  }
  final repository = ref.watch(groupRepositoryProvider);
  return repository.searchPublicGroups(query);
});

/// Provides suggested public groups that user hasn't joined yet
final suggestedGroupsProvider = StreamProvider.family<List<GroupModel>, String>((ref, userId) {
  final repository = ref.watch(groupRepositoryProvider);
  return repository.getSuggestedGroups(userId);
});

// ==================== ACTION PROVIDERS ====================

/// Provides access to group action methods
final groupActionsProvider = Provider<GroupActions>((ref) {
  return GroupActions(ref.watch(groupRepositoryProvider));
});

/// Class containing all group action methods
class GroupActions {
  final GroupRepository _repository;

  GroupActions(this._repository);

  /// Create a new group
  Future<String> createGroup({
    required String name,
    required String description,
    required String creatorId,
    required String creatorDisplayName,
    required GroupSettings settings,
  }) {
    return _repository.createGroup(
      name: name,
      description: description,
      creatorId: creatorId,
      creatorDisplayName: creatorDisplayName,
      settings: settings,
    );
  }

  /// Join an existing group
  Future<void> joinGroup(
    String groupId,
    String userId,
    String displayName,
  ) {
    return _repository.joinGroup(groupId, userId, displayName);
  }

  /// Leave a group
  Future<void> leaveGroup(String groupId, String userId) {
    return _repository.leaveGroup(groupId, userId);
  }

  /// Update group focus time after completing a session
  Future<void> updateGroupFocusTime(
    String groupId,
    String userId,
    int minutes,
  ) {
    return _repository.updateGroupFocusTime(groupId, userId, minutes);
  }

  /// Delete a group (admin only)
  Future<void> deleteGroup(String groupId) {
    return _repository.deleteGroup(groupId);
  }

  /// Check if user is member of a group
  Future<bool> isMember(String groupId, String userId) {
    return _repository.isMember(groupId, userId);
  }

  /// Check if user is admin of a group
  Future<bool> isAdmin(String groupId, String userId) {
    return _repository.isAdmin(groupId, userId);
  }
}



