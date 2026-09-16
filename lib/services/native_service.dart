import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pace/data/models/installed_app_model.dart';
import 'package:pace/presentation/providers/focus_session_provider.dart';

/// Service class to handle all native Android permissions required by the app.
/// This service communicates with the native Android side through method channels
/// to request and check various permissions needed for the app to function properly.
class NativeService {
  static const _platform = MethodChannel('com.lockin.focus/native');
  static const _eventChannel = EventChannel('com.lockin.focus/events');

  /// Initialize method handler to listen for native-initiated calls
  static void initializeMethodHandler(WidgetRef ref) {
    _platform.setMethodCallHandler((call) async {
      if (call.method == "force_sync_session") {
        // Trigger the notifier refresh logic
        ref.read(focusSessionProvider.notifier).refreshSessionFromNative();
      }
    });
  }


  // ============================================================================
  // FOCUS SESSION MANAGEMENT
  // ============================================================================

  /// Start a new focus session
  static Future<bool> startFocusSession({
    required String sessionId,
    required String userId,
    required int plannedDuration,
    required String sessionType,
    required List<String> blockedApps,
    List<Map<String, dynamic>>? blockedWebsites,
    bool shortFormBlocked = false,
    Map<String, dynamic>? shortFormBlocks,
    bool notificationsBlocked = false,
    Map<String, dynamic>? notificationBlocks,
  }) async {
    try {
      final result = await _platform.invokeMethod('startFocusSession', {
        'sessionId': sessionId,
        'userId': userId,
        'startTime': DateTime.now().millisecondsSinceEpoch,
        'plannedDuration': plannedDuration,
        'sessionType': sessionType,
        'timerMode': 'focus',
        'blockedApps': blockedApps,
        'blockedWebsites': blockedWebsites ?? [],
        'shortFormBlocked': shortFormBlocked,
        'shortFormBlocks': shortFormBlocks ?? {},
        'notificationsBlocked': notificationsBlocked,
        'notificationBlocks': notificationBlocks ?? {},
        'status': 'active',
      });
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error starting focus session: $e');
      return false;
    }
  }

  /// Pause current focus session
  static Future<bool> pauseFocusSession() async {
    try {
      final result = await _platform.invokeMethod('pauseFocusSession');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error pausing focus session: $e');
      return false;
    }
  }

  /// Resume paused focus session
  static Future<bool> resumeFocusSession() async {
    try {
      final result = await _platform.invokeMethod('resumeFocusSession');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error resuming focus session: $e');
      return false;
    }
  }

  /// End current focus session
  static Future<bool> endFocusSession() async {
    try {
      final result = await _platform.invokeMethod('endFocusSession');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error ending focus session: $e');
      return false;
    }
  }

  /// Get current session status
  static Future<Map<String, dynamic>?> getCurrentSessionStatus() async {
    try {
      final result = await _platform.invokeMethod('getCurrentSessionStatus');
      return result != null ? Map<String, dynamic>.from(result) : null;
    } catch (e) {
      debugPrint('Error getting session status: $e');
      return null;
    }
  }

  /// Stream of focus session events from native
  static Stream<Map<String, dynamic>> get focusEventStream {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }

  /// Check if the app has usage stats permission.
  /// This permission is required to monitor app usage and identify distracting apps.
  static Future<bool> hasUsageStatsPermission() async {
    try {
      final result = await _platform.invokeMethod('hasUsageStatsPermission');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking usage stats permission: $e');
      return false;
    }
  }

  /// Request usage stats permission from the user.
  /// Opens the device settings screen where the user can grant usage access.
  static Future<void> requestUsageStatsPermission() async {
    try {
      await _platform.invokeMethod('requestUsageStatsPermission');
    } catch (e) {
      debugPrint('Error requesting usage stats permission: $e');
    }
  }

  /// Check if the app has accessibility permission.
  /// This permission is required for advanced app blocking functionality.
  static Future<bool> hasAccessibilityPermission() async {
    try {
      final result = await _platform.invokeMethod('hasAccessibilityPermission');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking accessibility permission: $e');
      return false;
    }
  }

  /// Request accessibility permission from the user.
  /// Opens the accessibility settings screen where the user can enable the service.
  static Future<void> requestAccessibilityPermission() async {
    try {
      await _platform.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      debugPrint('Error requesting accessibility permission: $e');
    }
  }

  /// Check if the app has background execution permission.
  /// This permission allows the app to run continuously in the background.
  static Future<bool> hasBackgroundPermission() async {
    try {
      final result = await _platform.invokeMethod('hasBackgroundPermission');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking background permission: $e');
      return false;
    }
  }

  /// Request background permission for background tasks.
  /// This allows the app to continue monitoring even when not in foreground.
  static Future<void> requestBackgroundPermission() async {
    try {
      await _platform.invokeMethod('requestBackgroundPermission');
    } catch (e) {
      debugPrint('Error requesting background permission: $e');
    }
  }

  /// Check if the app has overlay permission (display over other apps).
  /// This permission is required to show blocking screens over other apps.
  static Future<bool> hasOverlayPermission() async {
    try {
      final result = await _platform.invokeMethod('hasOverlayPermission');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking overlay permission: $e');
      return false;
    }
  }

  /// Request overlay permission from the user.
  /// Opens the system settings where the user can allow displaying over other apps.
  static Future<void> requestOverlayPermission() async {
    try {
      await _platform.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
    }
  }

  /// Check if the app has display popup permission.
  /// This permission allows showing popup notifications and reminders.
  static Future<bool> hasDisplayPopupPermission() async {
    try {
      final result = await _platform.invokeMethod('hasDisplayPopupPermission');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking display popup permission: $e');
      return false;
    }
  }

  /// Request display popup permission from the user.
  /// This allows the app to show focus reminders and motivational popups.
  static Future<void> requestDisplayPopupPermission() async {
    try {
      await _platform.invokeMethod('requestDisplayPopupPermission');
    } catch (e) {
      debugPrint('Error requesting display popup permission: $e');
    }
  }

  /// Check if the app has notification permission.
  /// This permission is required to send notifications to the user.
  static Future<bool> hasNotificationPermission() async {
    try {
      final result = await _platform.invokeMethod('hasNotificationPermission');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking notification permission: $e');
      return false;
    }
  }

  /// Request notification permission from the user.
  /// Opens the notification settings or shows a system dialog.
  static Future<void> requestNotificationPermission() async {
    try {
      await _platform.invokeMethod('requestNotificationPermission');
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }
  }

  /// Debug method to get detailed accessibility permission information.
  /// Returns a detailed string with debugging information about accessibility service status.
  static Future<String> debugAccessibilityPermission() async {
    try {
      final result = await _platform.invokeMethod('debugAccessibilityPermission');
      return result as String? ?? 'No debug info available';
    } catch (e) {
      debugPrint('Error getting accessibility debug info: $e');
      return 'Error getting debug info: $e';
    }
  }



  /// Get all installed apps on the device.
  /// Returns a list of [InstalledApp] objects containing app information.
  /// Filters out most system apps and only includes user-installed apps
  /// and important system apps (Chrome, YouTube, Play Store, etc.).
  static Future<List<InstalledApp>> getInstalledApps() async {
    try {
      final result = await _platform.invokeMethod('getInstalledApps');

      if (result == null) {
        debugPrint('❌ getInstalledApps returned null');
        return [];
      }

      final List<dynamic> appsList = result as List<dynamic>;

      return appsList.map((app) {
        final Map<String, dynamic> appMap = Map<String, dynamic>.from(app as Map);
        return InstalledApp.fromMap(appMap);
      }).toList();
    } catch (e) {
      debugPrint('Error getting installed apps: $e');
      return [];
    }
  }

  static Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      final result = await _platform.invokeMethod('getAppIcon', {
        'packageName': packageName,
      });

      if (result == null) return null;

      return result as Uint8List;

    } on PlatformException catch (e) {
      // It's common for some system apps to fail icon retrieval, just log it lightly
      debugPrint("NativeService Icon Error ($packageName): '${e.message}'");
      return null;
    } catch (e) {
      debugPrint("NativeService Icon Error: $e");
      return null;
    }
  }

  // ============================================================================
  // PERSISTENT (ALWAYS-ON) BLOCKING
  // ============================================================================

  /// Set persistent app blocking (works even when no focus session is active)
  static Future<bool> setPersistentAppBlocking({
    required bool enabled,
    List<String>? blockedApps,
  }) async {
    try {
      await _platform.invokeMethod('setPersistentAppBlocking', {
        'enabled': enabled,
        'blockedApps': blockedApps,
      });
      return true;
    } catch (e) {
      debugPrint('Error setting persistent app blocking: $e');
      return false;
    }
  }

  /// Check if persistent app blocking is enabled
  static Future<bool> isPersistentAppBlockingEnabled() async {
    try {
      final result = await _platform.invokeMethod('isPersistentAppBlockingEnabled');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking persistent app blocking: $e');
      return false;
    }
  }

  /// Get list of persistently blocked apps
  static Future<List<String>> getPersistentBlockedApps() async {
    try {
      final result = await _platform.invokeMethod('getPersistentBlockedApps');
      if (result is List) {
        return result.cast<String>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting persistent blocked apps: $e');
      return [];
    }
  }

  /// Set persistent website blocking
  static Future<bool> setPersistentWebsiteBlocking({
    required bool enabled,
    List<Map<String, dynamic>>? blockedWebsites,
  }) async {
    try {
      await _platform.invokeMethod('setPersistentWebsiteBlocking', {
        'enabled': enabled,
        'blockedWebsites': blockedWebsites,
      });
      return true;
    } catch (e) {
      debugPrint('Error setting persistent website blocking: $e');
      return false;
    }
  }

  /// Check if persistent website blocking is enabled
  static Future<bool> isPersistentWebsiteBlockingEnabled() async {
    try {
      final result = await _platform.invokeMethod('isPersistentWebsiteBlockingEnabled');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking persistent website blocking: $e');
      return false;
    }
  }

  /// Get list of persistently blocked websites
  static Future<List<Map<String, dynamic>>> getPersistentBlockedWebsites() async {
    try {
      final result = await _platform.invokeMethod('getPersistentBlockedWebsites');
      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting persistent blocked websites: $e');
      return [];
    }
  }

  /// Set persistent short-form content blocking
  static Future<bool> setPersistentShortFormBlocking({
    required bool enabled,
    Map<String, dynamic>? shortFormBlocks,
  }) async {
    try {
      await _platform.invokeMethod('setPersistentShortFormBlocking', {
        'enabled': enabled,
        'shortFormBlocks': shortFormBlocks,
      });
      return true;
    } catch (e) {
      debugPrint('Error setting persistent short-form blocking: $e');
      return false;
    }
  }

  /// Check if persistent short-form blocking is enabled
  static Future<bool> isPersistentShortFormBlockingEnabled() async {
    try {
      final result = await _platform.invokeMethod('isPersistentShortFormBlockingEnabled');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking persistent short-form blocking: $e');
      return false;
    }
  }

  /// Get persistent short-form blocks
  static Future<Map<String, dynamic>> getPersistentShortFormBlocks() async {
    try {
      final result = await _platform.invokeMethod('getPersistentShortFormBlocks');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      debugPrint('Error getting persistent short-form blocks: $e');
      return {};
    }
  }

  /// Set persistent notification blocking
  static Future<bool> setPersistentNotificationBlocking({
    required bool enabled,
    Map<String, dynamic>? notificationBlocks,
  }) async {
    try {
      await _platform.invokeMethod('setPersistentNotificationBlocking', {
        'enabled': enabled,
        'notificationBlocks': notificationBlocks,
      });
      return true;
    } catch (e) {
      debugPrint('Error setting persistent notification blocking: $e');
      return false;
    }
  }

  /// Check if persistent notification blocking is enabled
  static Future<bool> isPersistentNotificationBlockingEnabled() async {
    try {
      final result = await _platform.invokeMethod('isPersistentNotificationBlockingEnabled');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking persistent notification blocking: $e');
      return false;
    }
  }

  /// Get persistent notification blocks
  static Future<Map<String, dynamic>> getPersistentNotificationBlocks() async {
    try {
      final result = await _platform.invokeMethod('getPersistentNotificationBlocks');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      debugPrint('Error getting persistent notification blocks: $e');
      return {};
    }
  }

  // ============================================================================
  // USAGE STATISTICS
  // ============================================================================

  /// Get app usage statistics for the specified number of days
  static Future<Map<String, dynamic>> getAppUsageStats({int days = 7}) async {
    try {
      final result = await _platform.invokeMethod('getAppUsageStats', {
        'days': days,
      });
      
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      
      return {
        'apps': <Map<String, dynamic>>[],
        'summary': {
          'totalAppsUsed': 0,
          'totalUsageMinutes': 0,
          'totalUsageHours': 0.0,
          'averageUsagePerApp': 0,
          'topApp': 'None',
          'daysAnalyzed': days,
          'error': 'Invalid response format'
        },
        'period': {
          'startTime': DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch,
          'endTime': DateTime.now().millisecondsSinceEpoch,
          'days': days,
        }
      };
    } catch (e) {
      debugPrint('Error getting app usage stats: $e');
      return {
        'apps': <Map<String, dynamic>>[],
        'summary': {
          'totalAppsUsed': 0,
          'totalUsageMinutes': 0,
          'totalUsageHours': 0.0,
          'averageUsagePerApp': 0,
          'topApp': 'None',
          'daysAnalyzed': days,
          'error': e.toString()
        },
        'period': {
          'startTime': DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch,
          'endTime': DateTime.now().millisecondsSinceEpoch,
          'days': days,
        }
      };
    }
  }

  /// Get today's usage statistics
  static Future<Map<String, dynamic>> getTodayUsageStats() async {
    try {
      final result = await _platform.invokeMethod('getTodayUsageStats');
      
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      
      return {
        'apps': <Map<String, dynamic>>[],
        'summary': {
          'totalAppsUsed': 0,
          'totalUsageMinutes': 0,
          'totalUsageHours': 0.0,
          'averageUsagePerApp': 0,
          'topApp': 'None',
          'daysAnalyzed': 1,
          'error': 'Invalid response format'
        },
        'period': {
          'startTime': DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0).millisecondsSinceEpoch,
          'endTime': DateTime.now().millisecondsSinceEpoch,
          'days': 1,
        }
      };
    } catch (e) {
      debugPrint('Error getting today\'s usage stats: $e');
      return {
        'apps': <Map<String, dynamic>>[],
        'summary': {
          'totalAppsUsed': 0,
          'totalUsageMinutes': 0,
          'totalUsageHours': 0.0,
          'averageUsagePerApp': 0,
          'topApp': 'None',
          'daysAnalyzed': 1,
          'error': e.toString()
        },
        'period': {
          'startTime': DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0).millisecondsSinceEpoch,
          'endTime': DateTime.now().millisecondsSinceEpoch,
          'days': 1,
        }
      };
    }
  }

  /// Get usage patterns (hourly breakdown for today)
  static Future<Map<String, dynamic>> getTodayUsagePatterns() async {
    try {
      final result = await _platform.invokeMethod('getTodayUsagePatterns');
      
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      
      return {
        'hourlyUsage': List.generate(24, (hour) => {
          'hour': hour,
          'usageMinutes': 0,
          'isCurrentHour': hour == DateTime.now().hour,
        }),
        'summary': {
          'totalUsageToday': 0,
          'peakHour': 0,
          'peakUsage': 0,
          'currentHour': DateTime.now().hour,
        }
      };
    } catch (e) {
      debugPrint('Error getting usage patterns: $e');
      return {
        'hourlyUsage': List.generate(24, (hour) => {
          'hour': hour,
          'usageMinutes': 0,
          'isCurrentHour': hour == DateTime.now().hour,
        }),
        'summary': {
          'totalUsageToday': 0,
          'peakHour': 0,
          'peakUsage': 0,
          'currentHour': DateTime.now().hour,
          'error': e.toString(),
        }
      };
    }
  }

  /// Get specific app usage stats
  static Future<Map<String, dynamic>> getAppSpecificUsage({
    required String packageName,
    int days = 7,
  }) async {
    try {
      final result = await _platform.invokeMethod('getAppSpecificUsage', {
        'packageName': packageName,
        'days': days,
      });
      
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      
      return {
        'appName': packageName,
        'packageName': packageName,
        'totalUsageMinutes': 0,
        'error': 'Invalid response format'
      };
    } catch (e) {
      debugPrint('Error getting app specific usage: $e');
      return {
        'appName': packageName,
        'packageName': packageName,
        'totalUsageMinutes': 0,
        'error': e.toString()
      };
    }
  }
}