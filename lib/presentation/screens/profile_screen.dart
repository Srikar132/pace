import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/parental_control_provider.dart';
import 'package:pace/presentation/providers/profile_provider.dart';
import 'package:pace/data/models/achievement_model.dart';
import 'package:pace/models/parental_control.dart';
import 'package:pace/widgets/parental_control_dialogs.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      data: (user) {
        if (user == null) {
          return const Scaffold(
            body: Center(child: Text('Please login first')),
          );
        }

        final parentalControlAsync = ref.watch(
          parentalControlProvider(user.uid),
        );
        final statsAsync = ref.watch(profileStatsProvider(user.uid));
        final achievementsAsync = ref.watch(achievementsProvider(user.uid));

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Header Section with Profile Picture
                  _buildHeader(context, user),

                  // Main Content
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Regain PRO Card
                        _buildProCard(context),

                        const SizedBox(height: 24),

                        // Parental Control Section
                        parentalControlAsync.when(
                          data: (parentalControl) =>
                              _buildParentalControlSection(
                                context,
                                ref,
                                user.uid,
                                parentalControl,
                              ),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, _) => const Text('Error loading settings'),
                        ),

                        const SizedBox(height: 24),

                        // Overview Section
                        _buildOverviewSection(context, statsAsync),

                        const SizedBox(height: 24),

                        // Achievements Section
                        _buildAchievementsSection(context, achievementsAsync),

                        const SizedBox(height: 24),

                        // Invite Friends Section
                        _buildInviteFriendsSection(context, ref, user.uid),

                        const SizedBox(height: 24),

                        // Weekly Reports Section
                        _buildWeeklyReportsSection(context),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }

  Widget _buildHeader(BuildContext context, user) {
    final focusingSince = DateFormat('MMM, yyyy').format(user.createdAt);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF82D65D), Color(0xFF6BB84D)],
        ),
      ),
      child: Column(
        children: [
          // Back Button and Settings
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () {
                    // TODO: Navigate to settings
                  },
                ),
              ],
            ),
          ),

          // Profile Picture
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF5CAF3C),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 3,
              ),
            ),
            child: user.photoURL != null
                ? ClipOval(
                    child: Image.network(
                      user.photoURL!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            (user.displayName ?? user.email)[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : Center(
                    child: Text(
                      (user.displayName ?? user.email)[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 12),

          // Add Photo Button (Overlay)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: Colors.white, size: 18),
                SizedBox(width: 4),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // User Name
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                user.displayName ?? user.email.split('@')[0],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit, color: Colors.white70, size: 18),
            ],
          ),

          const SizedBox(height: 4),

          // Focusing Since
          Text(
            'Focusing since $focusingSince',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Pace',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Unlock Strict mode and\nGo ad-free',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    // TODO: Navigate to upgrade screen
                  },
                  child: const Text(
                    'Upgrade to Pro',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF82D65D),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF82D65D),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Mascot
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF82D65D),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('🐸', style: TextStyle(fontSize: 48)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentalControlSection(
    BuildContext context,
    WidgetRef ref,
    String userId,
    ParentalControl parentalControl,
  ) {
    final service = ref.read(parentalControlServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Parental Control',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              // Parental Mode Toggle
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: parentalControl.isEnabled
                        ? const Color(0xFF82D65D).withValues(alpha: 0.2)
                        : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.lock,
                    color: parentalControl.isEnabled
                        ? const Color(0xFF82D65D)
                        : Colors.white54,
                    size: 24,
                  ),
                ),
                title: const Text(
                  'Parental Mode',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                subtitle: Text(
                  parentalControl.isEnabled
                      ? 'Apps are currently blocked'
                      : 'Apps are not blocked',
                  style: TextStyle(
                    fontSize: 13,
                    color: parentalControl.isEnabled
                        ? const Color(0xFF82D65D)
                        : Colors.white54,
                  ),
                ),
                trailing: Switch(
                  value: parentalControl.isEnabled,
                  activeThumbColor: const Color(0xFF82D65D),
                  onChanged: (value) async {
                    if (value) {
                      // Enabling parental mode
                      final hasPassword = await service.hasPassword(userId);
                      if (!hasPassword) {
                        // Show create password dialog
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => CreatePasswordDialog(
                              onConfirm: (password) async {
                                try {
                                  await service.setupParentalControl(
                                    userId: userId,
                                    password: password,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Parental mode enabled'),
                                        backgroundColor: Color(0xFF82D65D),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          );
                        }
                      } else {
                        // Just enable it
                        await service.enableParentalMode(userId);
                      }
                    } else {
                      // Disabling parental mode - require password
                      if (context.mounted) {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => VerifyPasswordDialog(
                            title: 'Disable Parental Mode',
                            description:
                                'Enter your parental control password to continue',
                            onVerify: (password) async {
                              final isValid = await service.verifyPassword(
                                userId: userId,
                                password: password,
                              );

                              if (isValid) {
                                await service.disableParentalMode(userId);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Parental mode disabled'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Incorrect password'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                              return isValid;
                            },
                          ),
                        );
                      }
                    }
                  },
                ),
              ),

              const Divider(color: Color(0xFF2A2A2A), height: 1),

              // Change Password
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.key, color: Colors.white54, size: 24),
                ),
                title: const Text(
                  'Change Password',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                subtitle: const Text(
                  'Update parental control password',
                  style: TextStyle(fontSize: 13, color: Colors.white54),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                ),
                onTap: () async {
                  final hasPassword = await service.hasPassword(userId);
                  if (!hasPassword) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enable parental mode first'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                    return;
                  }

                  if (context.mounted) {
                    // First verify current password
                    final verified = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => VerifyPasswordDialog(
                        title: 'Verify Identity',
                        description: 'Enter your current password',
                        onVerify: (password) async {
                          final isValid = await service.verifyPassword(
                            userId: userId,
                            password: password,
                          );
                          return isValid;
                        },
                      ),
                    );

                    // If verified, show create new password dialog
                    if (verified == true && context.mounted) {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => CreatePasswordDialog(
                          onConfirm: (newPassword) async {
                            try {
                              await service.changePassword(
                                userId: userId,
                                newPassword: newPassword,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Password changed successfully',
                                    ),
                                    backgroundColor: Color(0xFF82D65D),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      );
                    }
                  }
                },
              ),

              const Divider(color: Color(0xFF2A2A2A), height: 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewSection(
    BuildContext context,
    AsyncValue<dynamic> statsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        statsAsync.when(
          data: (stats) {
            return Column(
              children: [
                _buildStatCard(
                  icon: Icons.access_time,
                  iconColor: const Color(0xFF82D65D),
                  title: 'Total Time Saved',
                  value: stats.totalTimeSaved > 0
                      ? stats.getFormattedTimeSaved()
                      : '-',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF82D65D).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.center_focus_strong,
                          color: Color(0xFF82D65D),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Time Focused',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Come back tomorrow to see your progress! ✨',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF82D65D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('Error loading stats'),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection(
    BuildContext context,
    AsyncValue<List<AchievementModel>> achievementsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Your Achievements',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            TextButton(
              onPressed: () {
                // TODO: Show all achievements
              },
              child: const Text(
                'View all',
                style: TextStyle(color: Color(0xFF82D65D), fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        achievementsAsync.when(
          data: (achievements) {
            return SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: achievements.length,
                itemBuilder: (context, index) {
                  final achievement = achievements[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index < achievements.length - 1 ? 12 : 0,
                    ),
                    child: _buildAchievementCard(achievement),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('Error loading achievements'),
        ),
      ],
    );
  }

  Widget _buildAchievementCard(AchievementModel achievement) {
    final isLocked = !achievement.isUnlocked;

    return Container(
      width: 110,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isLocked
                  ? const Color(0xFF2A2A2A)
                  : const Color(0xFF82D65D).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isLocked
                  ? const Icon(Icons.lock, color: Colors.white38, size: 28)
                  : Text(
                      achievement.icon,
                      style: const TextStyle(fontSize: 32),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            achievement.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isLocked ? Colors.white38 : Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            achievement.description,
            style: TextStyle(
              fontSize: 10,
              color: isLocked ? Colors.white24 : Colors.white54,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildInviteFriendsSection(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Invite your friends',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                'Help your friends kill\nphone addiction',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildInviteProgressIndicator(1, true),
                  _buildInviteProgressIndicator(5, false),
                  _buildInviteProgressIndicator(10, false),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // Increment invites
                    await ref
                        .read(profileActionsProvider.notifier)
                        .incrementInvites(userId);

                    // Open WhatsApp share
                    final url = Uri.parse(
                      'https://wa.me/?text=Join me on Pace to beat phone addiction!',
                    );
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url);
                    }
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Invite friends'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF82D65D),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInviteProgressIndicator(int count, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF82D65D)
                  : const Color(0xFF2A2A2A),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                isActive ? '✓' : '',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count friend${count > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 10,
              color: isActive ? Colors.white : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyReportsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Weekly Reports',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF82D65D).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.description,
                  color: Color(0xFF82D65D),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dec ${DateTime.now().day - 7}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'View your weekly progress report',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white38,
                size: 16,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
