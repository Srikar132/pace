package com.example.pace.permissions

import android.app.Activity
import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.example.pace.services.LockInAccessibilityService
import java.lang.reflect.Method

class PermissionManager(private val activity: Activity) {



    companion object {
        private const val TAG = "PermissionManager"
        private const val USAGE_STATS_REQUEST_CODE = 1001
        private const val OVERLAY_REQUEST_CODE = 1002
        private const val ACCESSIBILITY_REQUEST_CODE = 1003
        private const val BACKGROUND_REQUEST_CODE = 1004
        private const val NOTIFICATION_REQUEST_CODE = 1005
    }

    // USAGE STATS PERMISSION
    fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            if (appOps == null) {
                Log.e(TAG, "AppOpsManager is null")
                return false
            }

            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    activity.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    activity.packageName
                )
            }
            val granted = mode == AppOpsManager.MODE_ALLOWED
            Log.d(TAG, "Usage Stats Permission: $granted (mode: $mode)")
            granted
        } catch (e: Exception) {
            Log.e(TAG, "Error checking usage stats permission", e)
            false
        }
    }

    fun requestUsageStatsPermission() {
        try {
            Log.d(TAG, "Requesting Usage Stats Permission")
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.data = Uri.parse("package:${activity.packageName}")
            activity.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error with package-specific intent, trying general intent", e)
            try {
                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                activity.startActivity(intent)
            } catch (ex: Exception) {
                Log.e(TAG, "Error requesting usage stats permission", ex)
            }
        }
    }

    // ACCESSIBILITY PERMISSION
    fun hasAccessibilityPermission(): Boolean {
        return try {
            // First check if accessibility is globally enabled
            val accessibilityEnabled = Settings.Secure.getInt(
                activity.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            ) == 1

            if (!accessibilityEnabled) {
                Log.d(TAG, "Accessibility is not globally enabled")
                return false
            }

            // Check if our specific accessibility service is enabled
            val enabledServices = Settings.Secure.getString(
                activity.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""

            // Try multiple possible service name formats
            val possibleServiceNames = listOf(
                "${activity.packageName}/.services.LockInAccessibilityService",
                "${activity.packageName}/com.example.pace.services.LockInAccessibilityService",
                "com.example.pace/.services.LockInAccessibilityService",
                "com.example.pace/com.example.pace.services.LockInAccessibilityService"
            )

            var serviceFound = false
            for (serviceName in possibleServiceNames) {
                if (enabledServices.contains(serviceName)) {
                    serviceFound = true
                    Log.d(TAG, "Found accessibility service: $serviceName")
                    break
                }
            }

            // Also check using AccessibilityManager (more reliable method)
            val accessibilityManager = activity.getSystemService(Context.ACCESSIBILITY_SERVICE) as? android.view.accessibility.AccessibilityManager
            
            var serviceRunning = false
            if (accessibilityManager != null) {
                val enabledServicesList = accessibilityManager.getEnabledAccessibilityServiceList(android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                
                for (serviceInfo in enabledServicesList) {
                    val serviceId = serviceInfo.id
                    Log.d(TAG, "Running accessibility service: $serviceId")
                    if (serviceId.contains("LockInAccessibilityService") || 
                        serviceId.contains(activity.packageName)) {
                        serviceRunning = true
                        Log.d(TAG, "Our accessibility service is running: $serviceId")
                        break
                    }
                }
            }

            // Also check if our service reports itself as running
            val serviceReportsRunning = LockInAccessibilityService.isServiceRunning

            val granted = serviceFound || serviceRunning || serviceReportsRunning

            Log.d(TAG, "Accessibility Permission Check:")
            Log.d(TAG, "- Global enabled: $accessibilityEnabled")
            Log.d(TAG, "- Service found in settings: $serviceFound")
            Log.d(TAG, "- Service actually running: $serviceRunning")
            Log.d(TAG, "- Service reports running: $serviceReportsRunning")
            Log.d(TAG, "- Final result: $granted")
            Log.d(TAG, "- Enabled services string: $enabledServices")

            granted
        } catch (e: Exception) {
            Log.e(TAG, "Error checking accessibility permission", e)
            false
        }
    }

    fun requestAccessibilityPermission() {
        try {
            Log.d(TAG, "Requesting Accessibility Permission")
            
            // First try to open the specific service settings
            try {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                // Add extra data to help navigate to our service
                intent.putExtra("android.provider.extra.ACCESSIBILITY_SERVICE_COMPONENT_NAME", 
                    "${activity.packageName}/.services.LockInAccessibilityService")
                activity.startActivity(intent)
                return
            } catch (e: Exception) {
                Log.w(TAG, "Failed to open specific accessibility service settings, opening general settings", e)
            }
            
            // Fallback to general accessibility settings
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            activity.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting accessibility permission", e)
        }
    }



    // BACKGROUND PERMISSION (Battery Optimization Exemption)
    fun hasBackgroundPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val powerManager = activity.getSystemService(Context.POWER_SERVICE) as? PowerManager
                if (powerManager == null) {
                    Log.e(TAG, "PowerManager is null")
                    return false
                }

                val packageName = activity.packageName
                val granted = powerManager.isIgnoringBatteryOptimizations(packageName)
                
                Log.d(TAG, "Background Permission Check:")
                Log.d(TAG, "  - Android Version: ${Build.VERSION.SDK_INT} (${Build.VERSION.RELEASE})")
                Log.d(TAG, "  - Package Name: $packageName")
                Log.d(TAG, "  - Is Ignoring Battery Optimizations: $granted")
                
                granted
            } catch (e: Exception) {
                Log.e(TAG, "Error checking background permission", e)
                false
            }
        } else {
            Log.d(TAG, "Background permission not needed for Android version < M (API 23)")
            true // Permission not needed for older Android versions
        }
    }

    fun requestBackgroundPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                Log.d(TAG, "Requesting Background Permission (Battery Optimization Exemption)")
                
                // First, try the direct package-specific intent
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    intent.data = Uri.parse("package:${activity.packageName}")
                    
                    Log.d(TAG, "Attempting to launch: ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS")
                    activity.startActivity(intent)
                    
                } catch (e: Exception) {
                    Log.w(TAG, "Direct battery optimization request failed, trying settings page", e)
                    
                    // If that fails, open the general battery optimization settings
                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    Log.d(TAG, "Attempting to launch: ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS")
                    activity.startActivity(intent)
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "Both battery optimization intents failed", e)
                
                // Last resort: try to open app info settings
                try {
                    Log.d(TAG, "Last resort: Opening app info settings")
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    intent.data = Uri.parse("package:${activity.packageName}")
                    activity.startActivity(intent)
                } catch (ex: Exception) {
                    Log.e(TAG, "Failed to open any settings page", ex)
                }
            }
        } else {
            Log.d(TAG, "Background permission not needed for Android version < M")
        }
    }

    // OVERLAY PERMISSION
    fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val granted = Settings.canDrawOverlays(activity)
            Log.d(TAG, "Overlay Permission: $granted")
            granted
        } else {
            Log.d(TAG, "Overlay permission not needed for Android version < M")
            true
        }
    }

    fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                Log.d(TAG, "Requesting Overlay Permission")
                val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                intent.data = Uri.parse("package:${activity.packageName}")
                activity.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Error requesting overlay permission", e)
            }
        }
    }

    // NOTIFICATION PERMISSION
    fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = NotificationManagerCompat.from(activity).areNotificationsEnabled()
            Log.d(TAG, "Notification Permission (API 33+): $granted")
            granted
        } else {
            val notificationManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val granted = notificationManager?.areNotificationsEnabled() ?: false
            Log.d(TAG, "Notification Permission: $granted")
            granted
        }
    }

    fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                Log.d(TAG, "Requesting Notification Permission (API 33+)")
                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                intent.putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                activity.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Error requesting notification permission", e)
            }
        } else {
            try {
                Log.d(TAG, "Opening app details for notification settings")
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                intent.data = Uri.parse("package:${activity.packageName}")
                activity.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Error opening app details", e)
            }
        }
    }

    fun hasDisplayPopupPermission(): Boolean {
        Log.d(TAG, "Display Popup Permission Check:")
        
        // 1. First, check standard Overlay permission (Baseline requirement)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(activity)) {
                Log.d(TAG, "  - Overlay permission not granted")
                return false
            }
        }

        // 2. SPECIFIC CHECK FOR XIAOMI (MIUI)
        // "Display pop-ups while running in background" is usually AppOps code 10021
        if (isXiaomi()) {
            Log.d(TAG, "  - Device is Xiaomi, checking MIUI-specific permission")
            try {
                val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
                if (appOps == null) {
                    Log.e(TAG, "AppOpsManager is null")
                    return true // Fallback to standard overlay check
                }

                val callingUid = android.os.Process.myUid()
                val pkgName = activity.packageName
                
                val appOpsClass = Class.forName(AppOpsManager::class.java.name)
                val checkOpMethod: Method = appOpsClass.getMethod(
                    "checkOpNoThrow", 
                    Int::class.javaPrimitiveType, 
                    Int::class.javaPrimitiveType, 
                    String::class.java
                )
                
                // 10021 is the magic number for OP_BACKGROUND_START_ACTIVITY on MIUI
                val opBackgroundStartActivity = 10021 
                val mode = checkOpMethod.invoke(appOps, opBackgroundStartActivity, callingUid, pkgName) as Int

                val allowed = mode == AppOpsManager.MODE_ALLOWED
                Log.d(TAG, "  - MIUI popup permission: $allowed (mode: $mode)")
                return allowed
            } catch (e: Exception) {
                Log.e(TAG, "Failed to check MIUI specific permission", e)
                // If reflection fails, we fallback to standard overlay check (better safe than sorry)
                return true 
            }
        }

        // For non-Xiaomi devices, the standard overlay permission is usually enough
        Log.d(TAG, "  - Non-Xiaomi device, using standard overlay check: true")
        return true
    }

    fun requestDisplayPopupPermission() {
        // 1. Try Xiaomi specific page first
        if (isXiaomi()) {
            try {
                val intent = Intent("miui.intent.action.APP_PERM_EDITOR")
                intent.setClassName("com.miui.securitycenter", "com.miui.permcenter.permissions.PermissionsEditorActivity")
                intent.putExtra("extra_pkgname", activity.packageName)
                activity.startActivity(intent)
                return
            } catch (e: Exception) {
                Log.e(TAG, "Failed to open MIUI permission page", e)
                // Continue to fallback if this fails
            }
        }

        // 2. Fallback: Open the App Info / Settings page for this app
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.parse("package:${activity.packageName}")
            activity.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open App Info settings", e)
            // Absolute last resort: Open general settings
            activity.startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    // Helper to detect Xiaomi devices
    fun isXiaomi(): Boolean {
        return Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true) || 
            Build.MANUFACTURER.equals("Redmi", ignoreCase = true) ||
            Build.MANUFACTURER.equals("Poco", ignoreCase = true)
    }

    // Add these to the end of PermissionManager class
    fun checkAllPermissions(): Map<String, Boolean> {
        return mapOf(
            "usageStats" to hasUsageStatsPermission(),
            "accessibility" to hasAccessibilityPermission(),
            "overlay" to hasOverlayPermission(),
            "background" to hasBackgroundPermission(),
            "notifications" to hasNotificationPermission(),
            "displayPopup" to hasDisplayPopupPermission()
        )
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // This is a placeholder for any specific logic you want to run after a settings activity returns
        Log.d("PermissionManager", "ActivityResult received: $requestCode")
    }

    fun cleanup() {
        // Perform any cleanup if necessary (e.g., removing listeners)
    }
}