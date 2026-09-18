import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/core/theme/app_theme.dart';
import 'package:pace/data/models/installed_app_model.dart';
import 'package:pace/models/block_app_bottom_model.dart';
import 'package:pace/models/model_manager.dart';
import 'package:pace/presentation/providers/app_management_provide.dart';
import 'package:pace/presentation/providers/blocked_content_provider.dart';
import 'package:pace/widgets/bottom_sheet_darg_handler.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/settings_provider.dart';

// ============================================================================
// OPTIMIZED: Extracted BlockedAppsSection to prevent unnecessary rebuilds
// ============================================================================
class _BlockedAppsSection extends ConsumerWidget {
  const _BlockedAppsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final blockedAppsAsync = user != null
        ? ref.watch(permanentlyBlockedAppsProvider(user.uid))
        : const AsyncValue<List<String>>.data([]);

    final blockedSet = blockedAppsAsync.maybeWhen(
      data: (apps) => Set<String>.from(apps),
      orElse: () => <String>{},
    );

    return GestureDetector(
      onTap: () async {
        // FIXED: Dismiss keyboard before opening new sheet
        FocusScope.of(context).unfocus();

        await BottomSheetManager.show(
          context: context,
          child: const BlockAppsSheet(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Text(
              'Blocked Apps',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            _BlockedAppsPreview(blockedSet: blockedSet),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// OPTIMIZED: Separate widget for blocked apps preview
// ============================================================================
class _BlockedAppsPreview extends ConsumerWidget {
  final Set<String> blockedSet;

  const _BlockedAppsPreview({required this.blockedSet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAppsAsync = ref.watch(installedAppsProvider);

    return allAppsAsync.when(
      data: (allApps) {
        final blockedAppsList = allApps
            .where((app) => blockedSet.contains(app.packageName))
            .take(3)
            .toList();

        if (blockedAppsList.isEmpty) {
          return Text(
            'None',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(child: _AppIconStack(apps: blockedAppsList)),
            const SizedBox(width: 12),
            Text(
              '${blockedSet.length} app${blockedSet.length != 1 ? 's' : ''}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => const SizedBox(),
    );
  }
}

// ============================================================================
// OPTIMIZED: Separate widget for icon stack with RepaintBoundary
// ============================================================================
class _AppIconStack extends StatelessWidget {
  final List<InstalledApp> apps;
  static const double iconSize = 24.0;
  static const double overlap = 14.0;

  const _AppIconStack({required this.apps});

  @override
  Widget build(BuildContext context) {
    final displayApps = apps.take(3).toList();

    return SizedBox(
      height: iconSize,
      width: iconSize + ((displayApps.length - 1) * overlap),
      child: Stack(
        children: List.generate(displayApps.length, (index) {
          final app = displayApps[index];
          return Positioned(
            left: index * overlap,
            child: RepaintBoundary(
              child: _AppIconCircle(
                packageName: app.packageName,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ============================================================================
// OPTIMIZED: Individual icon widget with caching
// ============================================================================
class _AppIconCircle extends ConsumerWidget {
  final String packageName;
  final Color backgroundColor;
  static const double iconSize = 24.0;

  const _AppIconCircle({
    required this.packageName,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconAsync = ref.watch(appIconProvider(packageName));

    return Container(
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: backgroundColor, width: 2),
        color: AppColors.surfaceElevated,
      ),
      child: ClipOval(
        child: iconAsync.when(
          data: (iconBytes) {
            if (iconBytes != null) {
              return Image.memory(
                iconBytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              );
            }
            return const Icon(Icons.android, size: 12, color: Colors.white);
          },
          loading: () => const SizedBox(),
          error: (_, _) =>
              const Icon(Icons.android, size: 12, color: Colors.white),
        ),
      ),
    );
  }
}

// ============================================================================
// MAIN WIDGET - Now handles settings internally
// ============================================================================
class FocusTimeBottomSheet extends ConsumerStatefulWidget {
  final Function() onSave;

  const FocusTimeBottomSheet({super.key, required this.onSave});

  @override
  ConsumerState<FocusTimeBottomSheet> createState() =>
      _FocusTimeBottomSheetState();
}

class _FocusTimeBottomSheetState extends ConsumerState<FocusTimeBottomSheet> {
  late int _duration;
  late int _breaks;
  late bool _blockHomeScreen;
  late bool _strictMode;
  late String _selectedMode;
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize settings from provider only once
    if (!_isInitialized) {
      final user = ref.read(currentUserProvider).value;
      if (user != null) {
        final settingsAsync = ref.read(userSettingsProvider(user.uid));
        settingsAsync.whenData((settings) {
          if (settings != null && mounted) {
            setState(() {
              _duration = settings.defaultDuration;
              _breaks = settings.numberOfBreaks;
              _blockHomeScreen = settings.blockPhoneHomeScreen;
              _strictMode = settings.strictMode;
              _selectedMode = settings.timerMode;
              _isInitialized = true;
            });
          }
        });
      }

      // Set defaults if settings not available
      if (!_isInitialized) {
        _duration = 25;
        _breaks = 0;
        _blockHomeScreen = false;
        _strictMode = false;
        _selectedMode = "timer";
        _isInitialized = true;
      }
    }
  }

  Future<void> _updateSettings({
    int? duration,
    int? breaks,
    bool? blockHome,
    bool? strict,
    String? mode,
  }) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    try {
      // Get current settings to copy from
      final currentSettings = ref.read(userSettingsProvider(user.uid)).value;
      if (currentSettings == null) return;

      final updated = currentSettings.copyWith(
        defaultDuration: duration ?? _duration,
        numberOfBreaks: breaks ?? _breaks,
        blockPhoneHomeScreen: blockHome ?? _blockHomeScreen,
        strictMode: strict ?? _strictMode,
        timerMode: mode ?? _selectedMode,
      );

      await ref
          .read(settingsRepositoryProvider)
          .updateSettings(user.uid, updated);
      // Refresh the provider so the UI stays in sync
      ref.invalidate(userSettingsProvider(user.uid));
    } catch (e) {
      debugPrint('Failed to update settings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;

    if (user == null) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.3,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(child: Text('Please login first')),
      );
    }

    final settingsAsync = ref.watch(userSettingsProvider(user.uid));

    return settingsAsync.when(
      data: (settings) => _buildContent(context, settings),
      loading: () => Container(
        height: MediaQuery.of(context).size.height * 0.3,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _buildContent(context, null),
    );
  }

  Widget _buildContent(BuildContext context, settings) {
    // Update state if settings loaded
    if (settings != null && !_isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _duration = settings.defaultDuration;
            _breaks = settings.numberOfBreaks;
            _blockHomeScreen = settings.blockPhoneHomeScreen;
            _strictMode = settings.strictMode;
            _selectedMode = settings.timerMode;
            _isInitialized = true;
          });
        }
      });
    }

    // FIXED: Account for keyboard
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final availableHeight = screenHeight - keyboardHeight;

    return Container(
      // FIXED: Use available height to prevent overflow
      height: availableHeight * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const BottomSheetDragHandle(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              // FIXED: Add keyboard padding
              child: Padding(
                padding: EdgeInsets.only(bottom: keyboardHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModeSelector(),
                    const SizedBox(height: 24),
                    _buildDurationSection(),
                    const SizedBox(height: 12),
                    _buildBreaksSection(),
                    const SizedBox(height: 24),
                    const Text(
                      'Block settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _BlockedAppsSection(),
                    const SizedBox(height: 12),
                    _buildToggleOption(
                      title: 'Block phone home screen',
                      value: _blockHomeScreen,
                      onChanged: (value) {
                        setState(() => _blockHomeScreen = value);
                        _updateSettings(blockHome: value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildStrictModeOption(),
                  ],
                ),
              ),
            ),
          ),
          // FIXED: Button stays at bottom, accounting for keyboard
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onSave();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Start Focus Now',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // OPTIMIZED: Cached color values
  static final _containerBgColor = Colors.white.withValues(alpha: 0.05);
  static final _borderColor = Colors.white.withValues(alpha: 0.1);
  static final _textSecondaryColor = Colors.white.withValues(alpha: 0.7);
  static final _iconColor = Colors.white.withValues(alpha: 0.5);

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildModeButton('Timer', _selectedMode == 'Timer'),
          _buildModeButton('Stopwatch', _selectedMode == 'Stopwatch'),
          // _buildModeButton('Pomodoro', _selectedMode == 'Pomodoro'),
        ],
      ),
    );
  }

  Widget _buildModeButton(String mode, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedMode = mode);
          _updateSettings(mode: mode);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            mode,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDurationSection() {
    return GestureDetector(
      onTap: _showDurationPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _containerBgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total duration',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Row(
              children: [
                Text(
                  '$_duration mins',
                  style: TextStyle(color: _textSecondaryColor, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: _iconColor, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreaksSection() {
    return GestureDetector(
      onTap: _showBreaksPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _containerBgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Breaks',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Row(
              children: [
                Text(
                  '$_breaks break${_breaks != 1 ? 's' : ''}',
                  style: TextStyle(color: _textSecondaryColor, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: _iconColor, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleOption({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _containerBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.white.withValues(alpha: 0.3),
              inactiveThumbColor: Colors.white.withValues(alpha: 0.5),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrictModeOption() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _containerBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Strict mode',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.premium,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _strictMode,
                  onChanged: (value) {
                    setState(() => _strictMode = value);
                    _updateSettings(strict: value);
                  },
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.white.withValues(alpha: 0.3),
                  inactiveThumbColor: Colors.white.withValues(alpha: 0.5),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'You cannot end your session early',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDurationPicker() {
    /* Keep empty as requested */
  }

  void _showBreaksPicker() {
    /* Keep empty as requested */
  }
}
