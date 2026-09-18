import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

/// Native service for managing blocks (apps, websites, short-form content)
///
/// This service communicates with the native Android Kotlin code to enforce
/// blocks at the OS level, not just in the Flutter app.
class BlocksNativeService {
  static const _methodChannel = MethodChannel('com.lockin.focus/native');
  static const _eventChannel = EventChannel('com.lockin.focus/events');

  /// Stream of blocking events from native Android service
  Stream<Map<String, dynamic>> get blockingEventsStream {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }

  // ==================== APP LIMITS ====================

  /// Set an app limit (time limit in minutes per day)
  Future<bool> setAppLimit({
    required String packageName,
    required int limitMinutes,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('setAppLimit', {
        'packageName': packageName,
        'limitMinutes': limitMinutes,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error setting app limit: $e');
      return false;
    }
  }

  /// Remove an app limit
  Future<bool> removeAppLimit(String packageName) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('removeAppLimit', {
        'packageName': packageName,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing app limit: $e');
      return false;
    }
  }

  /// Get remaining time for an app today (in minutes)
  Future<int> getRemainingTime(String packageName) async {
    try {
      final result = await _methodChannel.invokeMethod<int>(
        'getRemainingTime',
        {'packageName': packageName},
      );
      return result ?? 0;
    } catch (e) {
      debugPrint('Error getting remaining time: $e');
      return 0;
    }
  }

  /// Check if an app has exceeded its limit
  Future<bool> hasExceededLimit(String packageName) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'hasExceededLimit',
        {'packageName': packageName},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking if limit exceeded: $e');
      return false;
    }
  }

  /// Get today's usage time for an app (in minutes)
  Future<int> getTodayUsage(String packageName) async {
    try {
      final result = await _methodChannel.invokeMethod<int>('getTodayUsage', {
        'packageName': packageName,
      });
      return result ?? 0;
    } catch (e) {
      debugPrint('Error getting today usage: $e');
      return 0;
    }
  }

  /// Reset daily usage (typically called at midnight)
  Future<bool> resetDailyUsage() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('resetDailyUsage');
      return result ?? false;
    } catch (e) {
      debugPrint('Error resetting daily usage: $e');
      return false;
    }
  }

  // ==================== WEBSITE BLOCKS ====================

  /// Add or update a blocked website
  Future<bool> addBlockedWebsite({
    required String url,
    required String name,
    bool isActive = true,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'addBlockedWebsite',
        {'url': url, 'name': name, 'isActive': isActive},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error adding blocked website: $e');
      return false;
    }
  }

  /// Remove a blocked website
  Future<bool> removeBlockedWebsite(String url) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'removeBlockedWebsite',
        {'url': url},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing blocked website: $e');
      return false;
    }
  }

  /// Toggle website active/inactive status
  Future<bool> toggleBlockedWebsite(String url) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'toggleBlockedWebsite',
        {'url': url},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error toggling blocked website: $e');
      return false;
    }
  }

  /// Get all blocked websites
  Future<List<Map<String, dynamic>>> getBlockedWebsites() async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>(
        'getBlockedWebsites',
      );
      return result?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      debugPrint('Error getting blocked websites: $e');
      return [];
    }
  }

  /// Check if a URL is blocked
  Future<bool> isUrlBlocked(String url) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isUrlBlocked', {
        'url': url,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking if URL is blocked: $e');
      return false;
    }
  }

  // ==================== SHORT FORM BLOCKS ====================

  /// Set a short-form block (YouTube Shorts, Instagram Reels, etc.)
  Future<bool> setShortFormBlock({
    required String platform,
    required String feature,
    required bool isBlocked,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'setShortFormBlock',
        {'platform': platform, 'feature': feature, 'isBlocked': isBlocked},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error setting short-form block: $e');
      return false;
    }
  }

  /// Get all short-form blocks
  Future<List<Map<String, dynamic>>> getShortFormBlocks() async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>(
        'getShortFormBlocks',
      );
      return result?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      debugPrint('Error getting short-form blocks: $e');
      return [];
    }
  }

  /// Check if accessibility service is enabled (needed for short-form blocking)
  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isAccessibilityServiceEnabled',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking accessibility service: $e');
      return false;
    }
  }

  /// Test method to verify short-form blocking configuration
  Future<Map<String, dynamic>> getShortFormBlockingStatus() async {
    try {
      final result = await _methodChannel.invokeMethod(
        'getShortFormBlockingStatus',
      );

      if (result == null) {
        debugPrint('Native method returned null');
        return {};
      }

      debugPrint('Raw result type: ${result.runtimeType}');
      debugPrint('Raw result: $result');

      // Handle different possible return types
      if (result is Map<String, dynamic>) {
        return result;
      } else if (result is Map) {
        // Convert any map to Map<String, dynamic>
        final Map<String, dynamic> convertedMap = {};
        result.forEach((key, value) {
          final stringKey = key?.toString() ?? '';
          if (stringKey.isNotEmpty) {
            convertedMap[stringKey] = value;
          }
        });
        return convertedMap;
      } else {
        debugPrint('Unexpected result type: ${result.runtimeType}');
        return {};
      }
    } catch (e, stackTrace) {
      debugPrint('Error getting short-form blocking status: $e');
      debugPrint('Stack trace: $stackTrace');
      return {};
    }
  }

  /// Check if a platform's short-form content is blocked
  Future<bool> isShortFormBlocked({
    required String platform,
    required String feature,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isShortFormBlocked',
        {'platform': platform, 'feature': feature},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking if short-form is blocked: $e');
      return false;
    }
  }

  // ==================== HELPER METHODS ====================

  /// Sync Firebase blocks with native Android system
  /// This should be called when blocks are updated in Firebase
  Future<void> syncBlocksWithNative({
    required Map<String, Map<String, dynamic>> appLimits,
    required List<Map<String, dynamic>> blockedWebsites,
    required Map<String, Map<String, dynamic>> shortFormBlocks,
  }) async {
    try {
      // Sync app limits
      for (final entry in appLimits.entries) {
        final limit = entry.value;
        await setAppLimit(
          packageName: entry.key,
          limitMinutes: limit['dailyLimitMinutes'] as int,
        );
      }

      // Sync website blocks
      for (final website in blockedWebsites) {
        await addBlockedWebsite(
          url: website['url'] as String,
          name: website['name'] as String,
          isActive: website['isActive'] as bool? ?? true,
        );
      }

      // Sync short-form blocks
      for (final entry in shortFormBlocks.entries) {
        final block = entry.value;
        await setShortFormBlock(
          platform: block['platform'] as String,
          feature: block['feature'] as String,
          isBlocked: block['isBlocked'] as bool? ?? false,
        );
      }

      debugPrint('Successfully synced blocks with native Android');
    } catch (e) {
      debugPrint('Error syncing blocks with native: $e');
    }
  }

  // ==================== WEBSITE BLOCKING DIAGNOSTICS ====================

  /// Get website blocking diagnostics for testing
  Future<Map<String, dynamic>> getWebsiteBlockingDiagnostics() async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getWebsiteBlockingDiagnostics',
      );
      return result?.cast<String, dynamic>() ?? {};
    } catch (e) {
      debugPrint('Error getting website blocking diagnostics: $e');
      return {'error': 'Failed to get diagnostics', 'details': e.toString()};
    }
  }

  /// Test website blocking with a specific URL
  Future<bool> testWebsiteBlocking(String url) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'testWebsiteBlocking',
        {'url': url},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Error testing website blocking: $e');
      return false;
    }
  }

  /// Get list of supported browsers for website blocking
  Future<List<String>> getSupportedBrowsers() async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>(
        'getSupportedBrowsers',
      );
      return result?.cast<String>() ?? [];
    } catch (e) {
      debugPrint('Error getting supported browsers: $e');
      return [];
    }
  }

  /// Check the battery optimization status to ensure persistent background operation
  Future<Map<String, dynamic>> checkBatteryOptimizationStatus() async {
    try {
      final result = await _methodChannel.invokeMethod(
        'checkBatteryOptimizationStatus',
      );
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Error checking battery optimization status: $e');
      return {
        'isIgnoringBatteryOptimizations': false,
        'shouldRequest': false,
        'message': 'Unable to check battery optimization status',
      };
    }
  }

  /// Request battery optimization exemption for persistent blocking service
  Future<Map<String, dynamic>> requestBatteryOptimizationExemption() async {
    try {
      final result = await _methodChannel.invokeMethod(
        'requestBatteryOptimizationExemption',
      );
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Error requesting battery optimization exemption: $e');
      return {
        'granted': false,
        'message': 'Error requesting battery optimization exemption',
      };
    }
  }
}

/// Provider for BlocksNativeService
final blocksNativeServiceProvider = Provider<BlocksNativeService>((ref) {
  return BlocksNativeService();
});
