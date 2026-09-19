import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pace/core/theme/app_theme.dart';
import 'package:pace/data/models/installed_app_model.dart';
import 'package:pace/presentation/providers/app_management_provide.dart';
import 'package:pace/presentation/providers/blocked_content_provider.dart';
import 'package:pace/presentation/providers/auth_provider.dart';
import 'package:pace/presentation/providers/parental_control_provider.dart';
import 'package:pace/widgets/parental_control_dialogs.dart';

// ============================================================================
// FIXED: BlockAppsSheet with keyboard handling
// ============================================================================
class BlockAppsSheet extends ConsumerStatefulWidget {
  const BlockAppsSheet({super.key});

  @override
  ConsumerState<BlockAppsSheet> createState() => _BlockAppsSheetState();
}

class _BlockAppsSheetState extends ConsumerState<BlockAppsSheet> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;

  // Categories start expanded (matches previous default). Collapsing a
  // category removes its app rows from the flat row list below, instead of
  // resizing a non-virtualized Column - see _buildRows.
  final Set<String> _collapsedCategories = {};

  @override
  void initState() {
    super.initState();
    // appSearchQueryProvider is a global StateProvider (not scoped to this
    // sheet), so a query typed in a previous open would otherwise survive
    // close/reopen - the search box looks empty (fresh controller) but the
    // list stays filtered by the stale query. Riverpod forbids writing to a
    // provider synchronously during initState (throws "Tried to modify a
    // provider while the widget tree was building"), so defer to a
    // microtask - runs right after this build finishes, before the sheet is
    // actually shown to the user.
    Future.microtask(() {
      if (mounted) {
        ref.read(appSearchQueryProvider.notifier).state = '';
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    // groupedAppsProvider re-filters and re-sorts the full installed-apps
    // list synchronously; doing that on every keystroke is what was making
    // typing feel laggy. Debounce so a burst of keystrokes only recomputes
    // once, after typing pauses.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(appSearchQueryProvider.notifier).state = val;
      // Without this, a changed query updates the underlying list correctly
      // but the ListView stays at whatever scroll offset the previous
      // (narrower) result set left it at - a full list can look "stuck" on
      // the same few items if you're scrolled past where it ends.
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  // Flattens {category: apps} into a single row list so ListView.builder
  // only ever builds on-screen rows - regardless of how lopsided a
  // category's app count is (most apps land in one uncategorized "Other"
  // bucket, which used to render as one giant non-virtualized Column).
  //
  // Memoized: build() also reruns on every raw keyboard-inset frame (it
  // reads MediaQuery.viewInsets directly, see below), which has nothing to
  // do with the app/category data. Without this cache, that unrelated
  // rebuild was redoing this full O(n) flatten - 100-300 items - on every
  // single one of those frames during the keyboard animation. groupedApps
  // is a Riverpod Provider value, so it keeps the same object identity
  // across rebuilds unless its own inputs (search query, installed apps)
  // actually changed - cheap to compare by reference.
  Map<String, List<InstalledApp>>? _rowsCacheKey;
  List<_Row> _cachedRows = const [];

  List<_Row> _rowsFor(Map<String, List<InstalledApp>> groupedApps) {
    if (identical(groupedApps, _rowsCacheKey)) {
      return _cachedRows;
    }
    final rows = <_Row>[];
    for (final entry in groupedApps.entries) {
      final category = entry.key;
      final apps = entry.value;
      rows.add(_HeaderRow(category: category, apps: apps));
      if (!_collapsedCategories.contains(category)) {
        rows.addAll(apps.map(_AppRow.new));
      }
    }
    _rowsCacheKey = groupedApps;
    _cachedRows = rows;
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final groupedApps = ref.watch(groupedAppsProvider);
    final isLoading = ref.watch(installedAppsProvider).isLoading;
    final rows = _rowsFor(groupedApps);

    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      // Fixed height, independent of the keyboard - the sheet is
      // bottom-anchored, so shrinking this on every keyboard-animation
      // frame both forces a full repaint of this decorated background each
      // frame (expensive) AND visibly pushes the header/search bar downward
      // as it shrinks. Only the ListView area below yields to the keyboard
      // instead, via the trailing SizedBox.
      height: screenHeight * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          _buildSearchBar(context, ref),
          if (isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: RepaintBoundary(
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 30),
                  itemCount: rows.length,
                  cacheExtent: 500,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return switch (row) {
                      _HeaderRow() => _CategoryHeader(
                        key: ValueKey('header-${row.category}'),
                        category: row.category,
                        apps: row.apps,
                        isExpanded: !_collapsedCategories.contains(
                          row.category,
                        ),
                        onToggle: () => setState(() {
                          if (!_collapsedCategories.add(row.category)) {
                            _collapsedCategories.remove(row.category);
                          }
                          // groupedApps' identity doesn't change here, so
                          // the _rowsFor cache would otherwise return the
                          // stale (pre-toggle) row list.
                          _rowsCacheKey = null;
                        }),
                      ),
                      _AppRow() => _AppListTile(
                        key: ValueKey(row.app.packageName),
                        app: row.app,
                      ),
                    };
                  },
                ),
              ),
            ),
          // Absorbs the keyboard inset without resizing the outer
          // Container above - the Expanded ListView shrinks to make room
          // for this instead. AnimatedContainer (not a raw SizedBox) so
          // Flutter's own Tween smooths this: some OEM keyboards fire
          // viewInsets updates in uneven bursts rather than a steady
          // per-frame ramp, and reading that raw value directly would force
          // a synchronous relayout of the ListView above on every one of
          // those bursts - visible as stutter even when no single frame is
          // actually slow.
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: keyboardHeight,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Select Apps to Block',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 20),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search apps',
          prefixIcon: const Icon(Icons.search, color: AppColors.textDisabled),
          filled: true,
          fillColor: AppColors.surfaceElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
    );
  }
}

// ============================================================================
// Flat row model - lets ListView.builder virtualize app tiles across all
// categories, instead of each category's tiles being one non-virtualized
// Column (see _BlockAppsSheetState._buildRows).
// ============================================================================
sealed class _Row {
  const _Row();
}

class _HeaderRow extends _Row {
  final String category;
  final List<InstalledApp> apps;
  const _HeaderRow({required this.category, required this.apps});
}

class _AppRow extends _Row {
  final InstalledApp app;
  const _AppRow(this.app);
}

// ============================================================================
// Category header row - expand/collapse state now lives in
// _BlockAppsSheetState (drives which rows are in the flat list), this widget
// just renders the header + "block all in category" switch.
// ============================================================================
class _CategoryHeader extends ConsumerWidget {
  final String category;
  final List<InstalledApp> apps;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _CategoryHeader({
    super.key,
    required this.category,
    required this.apps,
    required this.isExpanded,
    required this.onToggle,
  });

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

    final blockedCount = apps
        .where((app) => blockedSet.contains(app.packageName))
        .length;
    final areAllBlocked = blockedCount == apps.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  category,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (blockedCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$blockedCount',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: areAllBlocked,
                  activeThumbColor: AppColors.accent,
                  inactiveTrackColor: AppColors.border,
                  onChanged: (bool value) async {
                    if (user == null) return;

                    // Check if trying to unblock and parental mode is enabled
                    if (!value && areAllBlocked) {
                      // Check parental control status
                      final parentalControlDoc = await FirebaseFirestore
                          .instance
                          .collection('parental_controls')
                          .doc(user.uid)
                          .get();

                      if (parentalControlDoc.exists) {
                        final data = parentalControlDoc.data();
                        final isEnabled = data?['isEnabled'] as bool? ?? false;

                        if (isEnabled && context.mounted) {
                          // Show PIN dialog
                          final verified = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => VerifyPasswordDialog(
                              title: 'Parental Control',
                              description: 'Enter PIN to unblock apps',
                              onVerify: (password) async {
                                final service = ref.read(
                                  parentalControlServiceProvider,
                                );
                                return await service.verifyPassword(
                                  userId: user.uid,
                                  password: password,
                                );
                              },
                            ),
                          );

                          if (verified != true) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('❌ Incorrect PIN or cancelled'),
                                  backgroundColor: Colors.red,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                            return;
                          }
                        }
                      }
                    }

                    final notifier = ref.read(
                      blockedContentNotifierProvider.notifier,
                    );

                    if (value) {
                      // Add all apps in this category
                      for (var app in apps) {
                        if (!blockedSet.contains(app.packageName)) {
                          await notifier.addPermanentlyBlockedApp(
                            user.uid,
                            app.packageName,
                          );
                        }
                      }
                    } else {
                      // Remove all apps in this category
                      for (var app in apps) {
                        if (blockedSet.contains(app.packageName)) {
                          await notifier.removePermanentlyBlockedApp(
                            user.uid,
                            app.packageName,
                          );
                        }
                      }
                    }
                  },
                ),
              ),
              AnimatedRotation(
                duration: const Duration(milliseconds: 200),
                turns: isExpanded ? 0.5 : 0,
                child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// OPTIMIZED: Individual App Tile
// ============================================================================
class _AppListTile extends ConsumerWidget {
  final InstalledApp app;

  const _AppListTile({super.key, required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final blockedAppsAsync = user != null
        ? ref.watch(permanentlyBlockedAppsProvider(user.uid))
        : const AsyncValue<List<String>>.data([]);

    final isBlocked = blockedAppsAsync.maybeWhen(
      data: (apps) => apps.contains(app.packageName),
      orElse: () => false,
    );

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              if (user == null) return;

              // Check if trying to unblock and parental mode is enabled
              if (isBlocked) {
                // Check parental control status
                final parentalControlDoc = await FirebaseFirestore.instance
                    .collection('parental_controls')
                    .doc(user.uid)
                    .get();

                if (parentalControlDoc.exists) {
                  final data = parentalControlDoc.data();
                  final isEnabled = data?['isEnabled'] as bool? ?? false;

                  if (isEnabled && context.mounted) {
                    // Show PIN dialog
                    final verified = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => VerifyPasswordDialog(
                        title: 'Parental Control',
                        description: 'Enter PIN to unblock ${app.appName}',
                        onVerify: (password) async {
                          final service = ref.read(
                            parentalControlServiceProvider,
                          );
                          return await service.verifyPassword(
                            userId: user.uid,
                            password: password,
                          );
                        },
                      ),
                    );

                    if (verified != true) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ Incorrect PIN or cancelled'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                  }
                }
              }

              final notifier = ref.read(
                blockedContentNotifierProvider.notifier,
              );
              if (isBlocked) {
                await notifier.removePermanentlyBlockedApp(
                  user.uid,
                  app.packageName,
                );
              } else {
                await notifier.addPermanentlyBlockedApp(
                  user.uid,
                  app.packageName,
                );
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _AppIcon(packageName: app.packageName),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      app.appName,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: isBlocked,
                      activeThumbColor: AppColors.accent,
                      inactiveTrackColor: AppColors.border,
                      onChanged: (bool value) async {
                        if (user == null) return;

                        // Check if trying to unblock and parental mode is enabled
                        if (!value && isBlocked) {
                          // Check parental control status
                          final parentalControlDoc = await FirebaseFirestore
                              .instance
                              .collection('parental_controls')
                              .doc(user.uid)
                              .get();

                          if (parentalControlDoc.exists) {
                            final data = parentalControlDoc.data();
                            final isEnabled =
                                data?['isEnabled'] as bool? ?? false;

                            if (isEnabled && context.mounted) {
                              // Show PIN dialog
                              final verified = await showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => VerifyPasswordDialog(
                                  title: 'Parental Control',
                                  description:
                                      'Enter PIN to unblock ${app.appName}',
                                  onVerify: (password) async {
                                    final service = ref.read(
                                      parentalControlServiceProvider,
                                    );
                                    return await service.verifyPassword(
                                      userId: user.uid,
                                      password: password,
                                    );
                                  },
                                ),
                              );

                              if (verified != true) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '❌ Incorrect PIN or cancelled',
                                      ),
                                      backgroundColor: Colors.red,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                                return;
                              }
                            }
                          }
                        }

                        final notifier = ref.read(
                          blockedContentNotifierProvider.notifier,
                        );
                        if (value) {
                          await notifier.addPermanentlyBlockedApp(
                            user.uid,
                            app.packageName,
                          );
                        } else {
                          await notifier.removePermanentlyBlockedApp(
                            user.uid,
                            app.packageName,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// OPTIMIZED: App Icon Widget
// ============================================================================
class _AppIcon extends ConsumerWidget {
  final String packageName;

  const _AppIcon({required this.packageName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconAsync = ref.watch(appIconProvider(packageName));

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: iconAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (err, stack) =>
              const Icon(Icons.android, color: Colors.white, size: 24),
          data: (iconBytes) {
            if (iconBytes == null) {
              return const Icon(Icons.android, color: Colors.white, size: 24);
            }
            return Image.memory(
              iconBytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.android, color: Colors.white, size: 24);
              },
            );
          },
        ),
      ),
    );
  }
}
