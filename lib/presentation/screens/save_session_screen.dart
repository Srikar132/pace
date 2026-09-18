import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pace/core/router/app_router.dart';
import 'package:pace/core/theme/app_theme.dart';
import 'package:pace/presentation/providers/focus_session_provider.dart';
import 'package:pace/core/constants/images.dart';

class SaveSessionScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> sessionData;

  const SaveSessionScreen({super.key, required this.sessionData});

  @override
  ConsumerState<SaveSessionScreen> createState() {
    return _SaveSessionScreenState();
  }
}

class _SaveSessionScreenState extends ConsumerState<SaveSessionScreen> {
  final TextEditingController _notesController = TextEditingController();
  String? _selectedTag;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '🎯 SaveSessionScreen: initState called with sessionData: ${widget.sessionData}',
    );
  }

  @override
  void dispose() {
    debugPrint('🎯 SaveSessionScreen: dispose called');
    _notesController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _getFormattedDuration() {
    final startTime = widget.sessionData['startTime'] as DateTime?;
    final endTime = DateTime.now();

    if (startTime != null) {
      final duration = endTime.difference(startTime);
      return _formatTime(duration.inSeconds);
    }

    final elapsedSeconds = widget.sessionData['elapsedSeconds'] as int? ?? 0;
    return _formatTime(elapsedSeconds);
  }

  String _getProductiveTime() {
    return _getFormattedDuration();
  }

  String _getDistractingTime() {
    return "0m";
  }

  String _getSessionName() {
    final now = DateTime.now();

    if (now.hour < 12) {
      return 'Morning session';
    } else if (now.hour < 17) {
      return 'Afternoon session';
    } else {
      return 'Evening session';
    }
  }

  String _getSessionTimeRange() {
    final startTime = widget.sessionData['startTime'] as DateTime?;
    final endTime = DateTime.now();

    if (startTime != null) {
      return '${_formatDateTime(startTime)} - ${_formatDateTime(endTime)}';
    }

    final now = DateTime.now();
    final elapsedSeconds = widget.sessionData['elapsedSeconds'] as int? ?? 0;
    final calculatedStart = now.subtract(Duration(seconds: elapsedSeconds));
    return '${_formatDateTime(calculatedStart)} - ${_formatDateTime(now)}';
  }

  String _formatDateTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _saveSession() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await ref
          .read(focusSessionProvider.notifier)
          .completeSessionWithNotes(
            notes: _notesController.text.trim(),
            tag: _selectedTag,
          );

      if (mounted) {
        context.go(splashRoute);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save session: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _discardSession() {
    // Captured before the bottom sheet's builder shadows `context` with its
    // own - needed afterward to navigate the actual screen, not the sheet.
    final screenContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 32),

            // Title
            const Text(
              'Delete this session?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Subtitle
            const Text(
              'This action cannot be undone.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Delete button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  ref.read(focusSessionProvider.notifier).discardSession();
                  // Route back through /splash so the router's redirect
                  // logic decides where to land, instead of duplicating
                  // that decision here.
                  screenContext.go(splashRoute);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Delete session',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Cancel button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(kHomeBackgroundImage, fit: BoxFit.cover),
          ),

          // Content
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 16.0,
                  ),
                  child: Column(
                    children: [
                      // Header
                      Text(
                        'Save session',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Time Range
                      Text(
                        _getSessionTimeRange(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Timer Circle
                      _buildTimerCircle(),

                      const SizedBox(height: 20),

                      // Stats Row
                      _buildStatsRow(),

                      const SizedBox(height: 16),

                      // Session Name
                      _buildSessionNameField(),

                      const SizedBox(height: 12),

                      // Notes Field
                      _buildNotesField(),

                      const SizedBox(height: 12),

                      // Tag Selection
                      _buildTagSelection(),

                      const Spacer(),

                      // Action Buttons
                      _buildActionButtons(),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerCircle() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.3),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _getFormattedDuration(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w300,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Total focus',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            iconColor: AppColors.accent,
            label: 'Productive',
            value: _getProductiveTime(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            iconColor: AppColors.warning,
            label: 'Distracting',
            value: _getDistractingTime(),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceElevated, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: Colors.white.withValues(alpha: 0.3),
            size: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionNameField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceElevated, width: 1),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.wb_sunny_rounded,
            color: AppColors.warning,
            size: 18,
          ),
        ),
        title: Text(
          _getSessionName(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.white.withValues(alpha: 0.3),
          size: 18,
        ),
      ),
    );
  }

  Widget _buildNotesField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceElevated, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.notes_rounded,
                color: AppColors.accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _notesController,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: 'Add notes here',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagSelection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceElevated, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.textDisabled.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.local_offer_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            const Text(
              'Tag',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _selectedTag ?? 'Untagged',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.white.withValues(alpha: 0.3),
          size: 20,
        ),
        onTap: () {
          // TODO: Show tag selection dialog
        },
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Save Button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.background,
              disabledBackgroundColor: AppColors.border,
              disabledForegroundColor: AppColors.textDisabled,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.background,
                      ),
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 12),

        // Delete Button
        TextButton(
          onPressed: _isSaving ? null : _discardSession,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.error,
            disabledForegroundColor: AppColors.textDisabled,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text(
            'Delete',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
