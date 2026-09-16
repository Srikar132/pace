import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/data/models/blocked_content_model.dart';
import 'package:pace/data/repositories/blocked_content_repository.dart';
import 'package:pace/services/native_service.dart';

// ============================================================================
// REPOSITORY PROVIDER
// ============================================================================
final blockedContentRepositoryProvider = Provider<BlockedContentRepository>((ref) {
  return BlockedContentRepository();
});

// ============================================================================
// MAIN DATA STREAM
// ============================================================================

// Stream all blocked content for a user
final blockedContentProvider = StreamProvider.family<BlockedContentModel, String>(
      (ref, userId) {
    return ref.watch(blockedContentRepositoryProvider).getBlockedContentStream(userId);
  },
);

// One-time fetch
final fetchBlockedContentProvider = FutureProvider.family<BlockedContentModel?, String>(
      (ref, userId) async {
    return ref.watch(blockedContentRepositoryProvider).getBlockedContent(userId);
  },
);

// ============================================================================
// DERIVED PROVIDERS (Fixed: Returns AsyncValue for UI .when)
// ============================================================================

// ✅ FIX: Use Provider instead of StreamProvider for derived data
// We watch the main provider and map the AsyncValue using .whenData
// This automatically handles Loading/Error states for you.

final blockedWebsitesProvider = Provider.family<AsyncValue<List<BlockedWebsite>>, String>((ref, userId) {
  final contentAsync = ref.watch(blockedContentProvider(userId));
  return contentAsync.when(
    data: (content) => AsyncValue.data(content.blockedWebsites),
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
  );
});

final shortFormBlocksProvider = Provider.family<AsyncValue<Map<String, ShortFormBlock>>, String>((ref, userId) {
  final contentAsync = ref.watch(blockedContentProvider(userId));
  return contentAsync.when(
    data: (content) => AsyncValue.data(content.shortFormBlocks),
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
  );
});

final permanentlyBlockedAppsProvider = Provider.family<AsyncValue<List<String>>, String>((ref, userId) {
  final contentAsync = ref.watch(blockedContentProvider(userId));
  return contentAsync.when(
    data: (content) => AsyncValue.data(content.permanentlyBlockedApps),
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
  );
});

// ============================================================================
// LOGIC PROVIDERS (State Helpers)
// ============================================================================

// Check if specific app is blocked
final isAppBlockedProvider = Provider.family<bool, ({String userId, String packageName})>((ref, params) {
  final asyncValue = ref.watch(permanentlyBlockedAppsProvider(params.userId));
  return asyncValue.maybeWhen(
    data: (apps) => apps.contains(params.packageName),
    orElse: () => false,
  );
});

// Check if specific website is blocked
final isWebsiteBlockedProvider = Provider.family<bool, ({String userId, String url})>((ref, params) {
  final asyncValue = ref.watch(blockedWebsitesProvider(params.userId));
  return asyncValue.maybeWhen(
    data: (websites) => websites.any((w) => w.isActive && w.url.contains(params.url)),
    orElse: () => false,
  );
});

// Check if specific short form is blocked
final isShortFormBlockedProvider = Provider.family<bool, ({String userId, String platform, String feature})>((ref, params) {
  final asyncValue = ref.watch(shortFormBlocksProvider(params.userId));
  final key = '${params.platform}_${params.feature}';

  return asyncValue.maybeWhen(
    data: (blocks) => blocks[key]?.isBlocked ?? false,
    orElse: () => false,
  );
});

// ============================================================================
// COUNTS PROVIDERS
// ============================================================================

final blockedAppsCountProvider = Provider.family<int, String>((ref, userId) {
  return ref.watch(permanentlyBlockedAppsProvider(userId)).maybeWhen(
    data: (apps) => apps.length,
    orElse: () => 0,
  );
});

final blockedWebsitesCountProvider = Provider.family<int, String>((ref, userId) {
  return ref.watch(blockedWebsitesProvider(userId)).maybeWhen(
    data: (websites) => websites.where((w) => w.isActive).length,
    orElse: () => 0,
  );
});

final blockedShortFormsCountProvider = Provider.family<int, String>((ref, userId) {
  return ref.watch(shortFormBlocksProvider(userId)).maybeWhen(
    data: (blocks) => blocks.values.where((b) => b.isBlocked).length,
    orElse: () => 0,
  );
});

// ============================================================================
// NATIVE PERSISTENT BLOCKING PROVIDERS  
// ============================================================================

// Native persistent app blocking status
final nativePersistentAppBlockingProvider = FutureProvider<bool>((ref) async {
  return await NativeService.isPersistentAppBlockingEnabled();
});

final nativePersistentBlockedAppsProvider = FutureProvider<List<String>>((ref) async {
  return await NativeService.getPersistentBlockedApps();
});

// Native persistent website blocking status
final nativePersistentWebsiteBlockingProvider = FutureProvider<bool>((ref) async {
  return await NativeService.isPersistentWebsiteBlockingEnabled();
});

final nativePersistentBlockedWebsitesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await NativeService.getPersistentBlockedWebsites();
});

// Native persistent short-form blocking status
final nativePersistentShortFormBlockingProvider = FutureProvider<bool>((ref) async {
  return await NativeService.isPersistentShortFormBlockingEnabled();
});

final nativePersistentShortFormBlocksProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await NativeService.getPersistentShortFormBlocks();
});

// Native persistent notification blocking status
final nativePersistentNotificationBlockingProvider = FutureProvider<bool>((ref) async {
  return await NativeService.isPersistentNotificationBlockingEnabled();
});

final nativePersistentNotificationBlocksProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await NativeService.getPersistentNotificationBlocks();
});

// ============================================================================
// COMBINED PROVIDERS (Firestore + Native)
// ============================================================================

/// Combined provider that shows if app blocking is active (either in Firestore or native)
final isAppBlockingActiveProvider = Provider.family<bool, String>((ref, userId) {
  final firestoreApps = ref.watch(permanentlyBlockedAppsProvider(userId));
  final nativeEnabled = ref.watch(nativePersistentAppBlockingProvider);

  return firestoreApps.whenData((apps) => apps.isNotEmpty).value == true ||
         nativeEnabled.whenData((enabled) => enabled).value == true;
});

/// Combined provider for website blocking status
final isWebsiteBlockingActiveProvider = Provider.family<bool, String>((ref, userId) {
  final firestoreWebsites = ref.watch(blockedWebsitesProvider(userId));
  final nativeEnabled = ref.watch(nativePersistentWebsiteBlockingProvider);

  return firestoreWebsites.whenData((websites) => websites.any((w) => w.isActive)).value == true ||
         nativeEnabled.whenData((enabled) => enabled).value == true;
});

/// Combined provider for short-form blocking status
final isShortFormBlockingActiveProvider = Provider.family<bool, String>((ref, userId) {
  final firestoreBlocks = ref.watch(shortFormBlocksProvider(userId));
  final nativeEnabled = ref.watch(nativePersistentShortFormBlockingProvider);

  return firestoreBlocks.whenData((blocks) => blocks.values.any((b) => b.isBlocked)).value == true ||
         nativeEnabled.whenData((enabled) => enabled).value == true;
});

/// Provider that returns a summary of all blocking statuses
final blockingSummaryProvider = Provider.family<Map<String, bool>, String>((ref, userId) {
  return {
    'apps': ref.watch(isAppBlockingActiveProvider(userId)),
    'websites': ref.watch(isWebsiteBlockingActiveProvider(userId)),
    'shortForm': ref.watch(isShortFormBlockingActiveProvider(userId)),
    'notifications': ref.watch(nativePersistentNotificationBlockingProvider).whenData((enabled) => enabled).value == true,
  };
});

/// Provider that checks if any blocking is active
final isAnyBlockingActiveProvider = Provider.family<bool, String>((ref, userId) {
  final summary = ref.watch(blockingSummaryProvider(userId));
  return summary.values.any((isActive) => isActive);
});

// ============================================================================
// STATE NOTIFIER (Actions)
// ============================================================================

class BlockedContentNotifier extends Notifier<AsyncValue<void>> {
  late final BlockedContentRepository _repository;

  @override
  AsyncValue<void> build() {
    _repository = ref.read(blockedContentRepositoryProvider);
    return const AsyncValue.data(null);
  }

  // Set or update blocked content
  Future<void> setBlockedContent(
      String userId,
      BlockedContentModel blockedContent,
      ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.setBlockedContent(userId, blockedContent);
    });
  }

  // Update specific fields
  Future<void> updateBlockedContent(
      String userId,
      Map<String, dynamic> updates,
      ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.updateBlockedContent(userId, updates);
    });
  }

  // === PERMANENTLY BLOCKED APPS ===

  Future<void> addPermanentlyBlockedApp(String userId, String packageName) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // 1. Update Firestore
      await _repository.addPermanentlyBlockedApp(userId, packageName);
      
      // 2. Get current blocked content to sync with native
      final content = await _repository.getBlockedContent(userId);
      if (content != null) {
        // 3. Update native persistent blocking
        await NativeService.setPersistentAppBlocking(
          enabled: content.permanentlyBlockedApps.isNotEmpty,
          blockedApps: content.permanentlyBlockedApps,
        );

        // 4. Invalidate native providers to refresh UI
        ref.invalidate(nativePersistentAppBlockingProvider);
        ref.invalidate(nativePersistentBlockedAppsProvider);
      }
      
      debugPrint('✅ Provider: Successfully added app $packageName and synced to native');
    });
  }

  Future<void> removePermanentlyBlockedApp(String userId, String packageName) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // 1. Update Firestore
      await _repository.removePermanentlyBlockedApp(userId, packageName);
      
      // 2. Get current blocked content to sync with native
      final content = await _repository.getBlockedContent(userId);
      if (content != null) {
        // 3. Update native persistent blocking
        await NativeService.setPersistentAppBlocking(
          enabled: content.permanentlyBlockedApps.isNotEmpty,
          blockedApps: content.permanentlyBlockedApps,
        );

        // 4. Invalidate native providers to refresh UI
        ref.invalidate(nativePersistentAppBlockingProvider);
        ref.invalidate(nativePersistentBlockedAppsProvider);
      }
      
      debugPrint('✅ Provider: Successfully removed app $packageName and synced to native');
    });
  }

  // === BLOCKED WEBSITES ===

  Future<void> addBlockedWebsite(String userId, BlockedWebsite website) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // 1. Update Firestore
      await _repository.addBlockedWebsite(userId, website);
      
      // 2. Get current blocked content to sync with native
      final content = await _repository.getBlockedContent(userId);
      if (content != null) {
        // Get active websites
        final activeWebsites = content.blockedWebsites.where((w) => w.isActive).toList();
        
        // 3. Update native persistent blocking
        await NativeService.setPersistentWebsiteBlocking(
          enabled: activeWebsites.isNotEmpty,
          blockedWebsites: activeWebsites.map((w) => w.toMap()).toList(),
        );

        // 4. Invalidate native providers to refresh UI
        ref.invalidate(nativePersistentWebsiteBlockingProvider);
        ref.invalidate(nativePersistentBlockedWebsitesProvider);
      }
      
      debugPrint('✅ Provider: Successfully added website ${website.url} and synced to native');
    });
  }

  Future<void> removeBlockedWebsite(String userId, String url) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // 1. Update Firestore
      await _repository.removeBlockedWebsite(userId, url);
      
      // 2. Get current blocked content to sync with native
      final content = await _repository.getBlockedContent(userId);
      if (content != null) {
        // Get active websites
        final activeWebsites = content.blockedWebsites.where((w) => w.isActive).toList();
        
        // 3. Update native persistent blocking
        await NativeService.setPersistentWebsiteBlocking(
          enabled: activeWebsites.isNotEmpty,
          blockedWebsites: activeWebsites.map((w) => w.toMap()).toList(),
        );

        // 4. Invalidate native providers to refresh UI
        ref.invalidate(nativePersistentWebsiteBlockingProvider);
        ref.invalidate(nativePersistentBlockedWebsitesProvider);
      }
      
      debugPrint('✅ Provider: Successfully removed website $url and synced to native');
    });
  }

  Future<void> toggleWebsiteBlockStatus(String userId, String url, bool isActive) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // 1. Update Firestore
      await _repository.toggleWebsiteBlockStatus(userId, url, isActive);
      
      // 2. Get current blocked content to sync with native
      final content = await _repository.getBlockedContent(userId);
      if (content != null) {
        // Get active websites
        final activeWebsites = content.blockedWebsites.where((w) => w.isActive).toList();
        
        // 3. Update native persistent blocking
        await NativeService.setPersistentWebsiteBlocking(
          enabled: activeWebsites.isNotEmpty,
          blockedWebsites: activeWebsites.map((w) => w.toMap()).toList(),
        );

        // 4. Invalidate native providers to refresh UI
        ref.invalidate(nativePersistentWebsiteBlockingProvider);
        ref.invalidate(nativePersistentBlockedWebsitesProvider);
      }
      
      debugPrint('✅ Provider: Successfully toggled website $url to $isActive and synced to native');
    });
  }

  // === SHORT FORM BLOCKS ===

  Future<void> setShortFormBlock(String userId, ShortFormBlock block) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // 1. Update Firestore
      await _repository.setShortFormBlock(userId, block);
      
      // 2. Get current blocked content to sync with native
      final content = await _repository.getBlockedContent(userId);
      if (content != null) {
        // Convert short-form blocks to native format
        final activeShortFormBlocks = content.shortFormBlocks.entries
            .where((entry) => entry.value.isBlocked)
            .fold<Map<String, dynamic>>({}, (map, entry) {
          map[entry.key] = entry.value.toMap();
          return map;
        });

        // 3. Update native persistent blocking
        await NativeService.setPersistentShortFormBlocking(
          enabled: activeShortFormBlocks.isNotEmpty,
          shortFormBlocks: activeShortFormBlocks,
        );

        // 4. Invalidate native providers to refresh UI
        ref.invalidate(nativePersistentShortFormBlockingProvider);
        ref.invalidate(nativePersistentShortFormBlocksProvider);
      }
      
      debugPrint('✅ Provider: Successfully set short form block and synced to native');
    });
  }

  Future<void> toggleShortFormBlockStatus(
      String userId,
      String platform,
      String feature,
      bool isBlocked,
      ) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // 1. Update Firestore
      await _repository.toggleShortFormBlockStatus(
        userId,
        platform,
        feature,
        isBlocked,
      );
      
      // 2. Get current blocked content to sync with native
      final content = await _repository.getBlockedContent(userId);
      if (content != null) {
        // Convert short-form blocks to native format
        final activeShortFormBlocks = content.shortFormBlocks.entries
            .where((entry) => entry.value.isBlocked)
            .fold<Map<String, dynamic>>({}, (map, entry) {
          map[entry.key] = entry.value.toMap();
          return map;
        });

        // 3. Update native persistent blocking
        await NativeService.setPersistentShortFormBlocking(
          enabled: activeShortFormBlocks.isNotEmpty,
          shortFormBlocks: activeShortFormBlocks,
        );

        // 4. Invalidate native providers to refresh UI
        ref.invalidate(nativePersistentShortFormBlockingProvider);
        ref.invalidate(nativePersistentShortFormBlocksProvider);
      }
      
      debugPrint('✅ Provider: Successfully updated $platform $feature to $isBlocked and synced to native');
    });
  }

  // ============================================================================
  // NATIVE PERSISTENT BLOCKING ACTIONS
  // ============================================================================

  /// Enable/disable persistent app blocking and sync with Firestore
  Future<void> setPersistentAppBlocking({
    required String userId,
    required bool enabled,
    List<String>? blockedApps,
    bool syncToFirestore = true,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // 1. Update native persistent blocking
      await NativeService.setPersistentAppBlocking(
        enabled: enabled,
        blockedApps: blockedApps,
      );

      // 2. Sync to Firestore if requested
      if (syncToFirestore && blockedApps != null) {
        await _repository.updateBlockedContent(userId, {
          'permanentlyBlockedApps': blockedApps,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }

      // 3. Invalidate cache to refresh UI
      ref.invalidate(nativePersistentAppBlockingProvider);
      ref.invalidate(nativePersistentBlockedAppsProvider);
    });
  }

  /// Enable/disable persistent website blocking and sync with Firestore
  Future<void> setPersistentWebsiteBlocking({
    required String userId,
    required bool enabled,
    List<BlockedWebsite>? blockedWebsites,
    bool syncToFirestore = true,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // Convert BlockedWebsite objects to Map for native
      final websiteMaps = blockedWebsites?.map((w) => w.toMap()).toList();

      // 1. Update native persistent blocking
      await NativeService.setPersistentWebsiteBlocking(
        enabled: enabled,
        blockedWebsites: websiteMaps,
      );

      // 2. Sync to Firestore if requested
      if (syncToFirestore && blockedWebsites != null) {
        await _repository.updateBlockedContent(userId, {
          'blockedWebsites': blockedWebsites.map((w) => w.toMap()).toList(),
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }

      // 3. Invalidate cache to refresh UI
      ref.invalidate(nativePersistentWebsiteBlockingProvider);
      ref.invalidate(nativePersistentBlockedWebsitesProvider);
    });
  }

  /// Enable/disable persistent short-form content blocking and sync with Firestore
  Future<void> setPersistentShortFormBlocking({
    required String userId,
    required bool enabled,
    Map<String, ShortFormBlock>? shortFormBlocks,
    bool syncToFirestore = true,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // Convert ShortFormBlock objects to Map for native
      final blockMaps = shortFormBlocks?.map((key, value) => MapEntry(key, value.toMap()));

      // 1. Update native persistent blocking
      await NativeService.setPersistentShortFormBlocking(
        enabled: enabled,
        shortFormBlocks: blockMaps,
      );

      // 2. Sync to Firestore if requested
      if (syncToFirestore && shortFormBlocks != null) {
        final blocksMap = shortFormBlocks.map((key, value) => MapEntry(key, value.toMap()));
        await _repository.updateBlockedContent(userId, {
          'shortFormBlocks': blocksMap,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }

      // 3. Invalidate cache to refresh UI
      ref.invalidate(nativePersistentShortFormBlockingProvider);
      ref.invalidate(nativePersistentShortFormBlocksProvider);
    });
  }

  /// Enable/disable persistent notification blocking (no Firestore equivalent currently)
  Future<void> setPersistentNotificationBlocking({
    required bool enabled,
    Map<String, dynamic>? notificationBlocks,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // Update native persistent blocking
      await NativeService.setPersistentNotificationBlocking(
        enabled: enabled,
        notificationBlocks: notificationBlocks,
      );

      // Invalidate cache to refresh UI
      ref.invalidate(nativePersistentNotificationBlockingProvider);
      ref.invalidate(nativePersistentNotificationBlocksProvider);
    });
  }

  /// Sync Firestore blocked content to native persistent blocking
  Future<void> syncFirestoreToNative(String userId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final content = await _repository.getBlockedContent(userId);
      if (content != null) {
        // Sync apps
        if (content.permanentlyBlockedApps.isNotEmpty) {
          await NativeService.setPersistentAppBlocking(
            enabled: true,
            blockedApps: content.permanentlyBlockedApps,
          );
        }

        // Sync websites
        if (content.blockedWebsites.isNotEmpty) {
          final activeWebsites = content.blockedWebsites.where((w) => w.isActive).toList();
          if (activeWebsites.isNotEmpty) {
            await NativeService.setPersistentWebsiteBlocking(
              enabled: true,
              blockedWebsites: activeWebsites.map((w) => w.toMap()).toList(),
            );
          }
        }

        // Sync short-form blocks
        final activeShortFormBlocks = content.shortFormBlocks.entries
            .where((entry) => entry.value.isBlocked)
            .fold<Map<String, dynamic>>({}, (map, entry) {
          map[entry.key] = entry.value.toMap();
          return map;
        });

        if (activeShortFormBlocks.isNotEmpty) {
          await NativeService.setPersistentShortFormBlocking(
            enabled: true,
            shortFormBlocks: activeShortFormBlocks,
          );
        }
      }

      // Invalidate all caches
      ref.invalidate(nativePersistentAppBlockingProvider);
      ref.invalidate(nativePersistentBlockedAppsProvider);
      ref.invalidate(nativePersistentWebsiteBlockingProvider);
      ref.invalidate(nativePersistentBlockedWebsitesProvider);
      ref.invalidate(nativePersistentShortFormBlockingProvider);
      ref.invalidate(nativePersistentShortFormBlocksProvider);
    });
  }

  /// Sync native persistent blocking to Firestore
  Future<void> syncNativeToFirestore(String userId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final updates = <String, dynamic>{
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      // Sync apps
      final isAppBlockingEnabled = await NativeService.isPersistentAppBlockingEnabled();
      if (isAppBlockingEnabled) {
        final blockedApps = await NativeService.getPersistentBlockedApps();
        updates['permanentlyBlockedApps'] = blockedApps;
      }

      // Sync websites
      final isWebsiteBlockingEnabled = await NativeService.isPersistentWebsiteBlockingEnabled();
      if (isWebsiteBlockingEnabled) {
        final blockedWebsites = await NativeService.getPersistentBlockedWebsites();
        // Convert to BlockedWebsite objects
        final websites = blockedWebsites.map((w) => BlockedWebsite.fromMap(w)).toList();
        updates['blockedWebsites'] = websites.map((w) => w.toMap()).toList();
      }

      // Sync short-form blocks
      final isShortFormBlockingEnabled = await NativeService.isPersistentShortFormBlockingEnabled();
      if (isShortFormBlockingEnabled) {
        final shortFormBlocks = await NativeService.getPersistentShortFormBlocks();
        // Convert to ShortFormBlock objects
        final blocks = shortFormBlocks.map((key, value) {
          return MapEntry(key, ShortFormBlock.fromMap(Map<String, dynamic>.from(value)));
        });
        updates['shortFormBlocks'] = blocks.map((key, value) => MapEntry(key, value.toMap()));
      }

      // Update Firestore
      await _repository.updateBlockedContent(userId, updates);
    });
  }
}

// Notifier Provider
final blockedContentNotifierProvider = NotifierProvider<BlockedContentNotifier, AsyncValue<void>>(() {
  return BlockedContentNotifier();
});