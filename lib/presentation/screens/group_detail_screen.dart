import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/data/models/group_memeber_model.dart';
import 'package:pace/data/models/group_model.dart';
import 'package:pace/presentation/providers/group_provider.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Generate consistent color for group based on name
Color _getGroupColor(String groupName) {
  final colors = [
    const Color(0xFF82D65D), // Green
    const Color(0xFF6B9BD6), // Blue
    const Color(0xFFE57373), // Red
    const Color(0xFFFFB74D), // Orange
    const Color(0xFF9575CD), // Purple
    const Color(0xFF4DB6AC), // Teal
    const Color(0xFFFFD54F), // Yellow
    const Color(0xFFFF8A65), // Deep Orange
    const Color(0xFF81C784), // Light Green
    const Color(0xFF64B5F6), // Light Blue
  ];
  
  int hash = 0;
  for (int i = 0; i < groupName.length; i++) {
    hash = groupName.codeUnitAt(i) + ((hash << 5) - hash);
  }
  
  return colors[hash.abs() % colors.length];
}

/// Detailed view of a specific group with members and leaderboard
class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupProvider(widget.groupId));
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: groupAsync.when(
        data: (group) {
          if (group == null) return _buildErrorState('Group not found');

          final isAdmin = user != null && group.isAdmin(user.uid);
          final isMember = user != null && group.isMember(user.uid);
          final isCreator = user != null && group.isCreator(user.uid);

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                stretch: true,
                backgroundColor: const Color(0xFF1A1A1A),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  if (isMember)
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white),
                      onPressed: () => _shareGroup(group),
                    ),
                  if (isAdmin)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: const Color(0xFF2D2D2D),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (value) {
                        if (value == 'delete' && isCreator) _deleteGroup(group);
                      },
                      itemBuilder: (context) => [
                        if (isCreator)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete Group', style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF82D65D).withOpacity(0.3),
                          const Color(0xFF1A1A1A),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      _getGroupColor(group.name),
                                      _getGroupColor(group.name).withOpacity(0.7),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _getGroupColor(group.name).withOpacity(0.4),
                                      blurRadius: 15,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                group.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.people, color: Colors.white, size: 12),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${group.memberIds.length} members',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (group.settings.isPublic)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF82D65D).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.public, color: Color(0xFF82D65D), size: 12),
                                          SizedBox(width: 4),
                                          Text(
                                            'Public',
                                            style: TextStyle(
                                              color: Color(0xFF82D65D),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.access_time,
                          label: 'Total Focus',
                          value: group.getFormattedFocusTime(),
                          color: const Color(0xFF82D65D),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.emoji_events,
                          label: 'Daily Goal',
                          value: group.settings.focusGoalMinutes > 0
                              ? '${group.settings.focusGoalMinutes}m'
                              : 'None',
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF82D65D).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.description, color: Color(0xFF82D65D), size: 16),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'About',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          group.description,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ];
            },
            body: membersAsync.when(
              data: (members) {
                return Column(
                  children: [
                    Container(
                      color: const Color(0xFF1A1A1A),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFF82D65D),
                        unselectedLabelColor: Colors.white54,
                        indicatorColor: const Color(0xFF82D65D),
                        indicatorWeight: 3,
                        tabs: const [
                          Tab(icon: Icon(Icons.people, size: 20), text: 'Members'),
                          Tab(icon: Icon(Icons.emoji_events, size: 20), text: 'Leaderboard'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _buildMembersTab(members, group),
                          _buildLeaderboardTab(members, group),
                        ],
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF82D65D)),
              ),
              error: (error, stack) => _buildErrorState('Error loading members: $error'),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF82D65D))),
        error: (error, stack) => _buildErrorState('Error: $error'),
      ),
      bottomNavigationBar: groupAsync.whenData((group) {
        if (group == null) return null;
        final user = ref.watch(authStateProvider).value;
        if (user == null) return null;

        final isMember = group.isMember(user.uid);
        final isCreator = group.isCreator(user.uid);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: isMember
                ? (isCreator ? null : _buildLeaveButton(group))
                : _buildJoinButton(group),
          ),
        );
      }).value,
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTab(List<GroupMemberModel> members, GroupModel group) {
    if (members.isEmpty) {
      return const Center(child: Text('No members yet', style: TextStyle(color: Colors.white54)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: members.length,
      cacheExtent: 500,
      itemBuilder: (context, index) {
        final member = members[index];
        final isAdmin = group.isAdmin(member.userId);
        final isCreator = group.isCreator(member.userId);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCreator
                  ? const Color(0xFF82D65D).withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF82D65D).withOpacity(0.2),
                    child: Text(
                      member.displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF82D65D),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (isCreator)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF82D65D),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF2D2D2D), width: 2),
                        ),
                        child: const Icon(Icons.star, color: Colors.black, size: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCreator) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF82D65D).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'CREATOR',
                              style: TextStyle(
                                color: Color(0xFF82D65D),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ] else if (isAdmin) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ADMIN',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time, color: Colors.white54, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${member.getFormattedFocusTime()} focused',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeaderboardTab(List<GroupMemberModel> members, GroupModel group) {
    if (!group.settings.showLeaderboard) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_off, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text('Leaderboard is disabled', style: TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      );
    }

    final sortedMembers = List<GroupMemberModel>.from(members);

    if (sortedMembers.isEmpty) {
      return const Center(child: Text('No members yet', style: TextStyle(color: Colors.white54)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: sortedMembers.length,
      cacheExtent: 500,
      itemBuilder: (context, index) {
        final member = sortedMembers[index];
        final rank = index + 1;
        final medal = member.getMedalEmoji();

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: rank <= 3
                  ? (rank == 1
                      ? Colors.amber.withOpacity(0.5)
                      : rank == 2
                          ? Colors.grey.withOpacity(0.5)
                          : Colors.brown.withOpacity(0.5))
                  : Colors.white.withOpacity(0.1),
              width: rank <= 3 ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: rank <= 3
                      ? (rank == 1
                          ? Colors.amber.withOpacity(0.2)
                          : rank == 2
                              ? Colors.grey.withOpacity(0.2)
                              : Colors.brown.withOpacity(0.2))
                      : const Color(0xFF82D65D).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: medal != null
                      ? Text(medal, style: const TextStyle(fontSize: 20))
                      : Text(
                          '#$rank',
                          style: const TextStyle(
                            color: Color(0xFF82D65D),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time, color: Color(0xFF82D65D), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          member.getFormattedFocusTime(),
                          style: const TextStyle(
                            color: Color(0xFF82D65D),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (rank <= 3)
                Icon(
                  Icons.emoji_events,
                  color: rank == 1 ? Colors.amber : rank == 2 ? Colors.grey : Colors.brown,
                  size: 24,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJoinButton(GroupModel group) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: () => _joinGroup(group),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF82D65D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_add, color: Colors.black, size: 20),
            SizedBox(width: 8),
            Text(
              'Join Group',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveButton(GroupModel group) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: () => _leaveGroup(group),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.exit_to_app, color: Colors.red, size: 20),
            SizedBox(width: 8),
            Text(
              'Leave Group',
              style: TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.withOpacity(0.5)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF82D65D)),
            child: const Text('Go Back', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _shareGroup(GroupModel group) {
    Share.share(
      '🎯 Join my focus group "${group.name}" on Pace!\n\n'
      '${group.description}\n\n'
      '👥 ${group.memberIds.length} members\n'
      '⏱️ ${group.getFormattedFocusTime()} total focus time\n\n'
      'Group ID: ${group.id}',
      subject: 'Join my focus group: ${group.name}',
    );
  }

  Future<void> _joinGroup(GroupModel group) async {
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      final groupActions = ref.read(groupActionsProvider);
      await groupActions.joinGroup(
        group.id,
        user.uid,
        user.displayName ?? user.email?.split('@')[0] ?? 'User',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Successfully joined "${group.name}"!')),
              ],
            ),
            backgroundColor: const Color(0xFF82D65D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _leaveGroup(GroupModel group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Group?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to leave "${group.name}"?\n\nYour focus time contributions will remain.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      final groupActions = ref.read(groupActionsProvider);
      await groupActions.leaveGroup(group.id, user.uid);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Left group successfully'),
            backgroundColor: Color(0xFF82D65D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteGroup(GroupModel group) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever, color: Colors.red, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Delete Group?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone!',
                      style: TextStyle(
                        color: Colors.red.shade200,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'All group data, members, and focus time records will be permanently deleted.',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"${group.name}"',
                style: const TextStyle(
                  color: Color(0xFF82D65D),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Delete Forever',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      ),
    );

    if (confirm != true) return;

    try {
      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF82D65D)),
                  SizedBox(height: 16),
                  Text(
                    'Deleting group...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      final groupActions = ref.read(groupActionsProvider);
      await groupActions.deleteGroup(group.id);

      if (mounted) {
        // Close loading dialog
        Navigator.pop(context);
        
        // Navigate back to groups tab with smooth animation
        Navigator.pop(context);
        
        // Show success message
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Group "${group.name}" deleted successfully'),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF82D65D),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        // Close loading dialog if open
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Error deleting group: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }
}