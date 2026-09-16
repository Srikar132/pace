package com.example.pace.services.shared

import android.Manifest
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.annotation.RequiresPermission

/**
 * MonitoringHelper - Shared utility functions for monitoring services
 *
 * PROVIDES:
 * - Current foreground app detection
 * - App name resolution
 * - Usage stats queries
 * - Permission checks
 */
object MonitoringHelper {

    private const val TAG = "MonitoringHelper"

    /**
     * Get the currently active foreground app
     */
    @RequiresPermission(Manifest.permission.PACKAGE_USAGE_STATS)
    fun getCurrentForegroundApp(context: Context): String {
        return try {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

            val endTime = System.currentTimeMillis()
            val beginTime = endTime - 2000 // Last 2 seconds

            val usageEvents = usageStatsManager.queryEvents(beginTime, endTime)
            var lastApp = ""

            while (usageEvents.hasNextEvent()) {
                val event = UsageEvents.Event()
                usageEvents.getNextEvent(event)

                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    lastApp = event.packageName
                }
            }

            lastApp

        } catch (e: Exception) {
            Log.e(TAG, "Error getting foreground app", e)
            ""
        }
    }

    /**
     * Get app name from package name
     */
    fun getAppName(context: Context, packageName: String): String {
        return try {
            val pm = context.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            packageName
        } catch (e: Exception) {
            Log.e(TAG, "Error getting app name for $packageName", e)
            packageName
        }
    }

    /**
     * Get today's usage for a specific app in minutes
     */
    @RequiresPermission(Manifest.permission.PACKAGE_USAGE_STATS)
    fun getTodayUsageMinutes(context: Context, packageName: String): Int {
        return try {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

            val calendar = java.util.Calendar.getInstance()
            calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
            calendar.set(java.util.Calendar.MINUTE, 0)
            calendar.set(java.util.Calendar.SECOND, 0)
            calendar.set(java.util.Calendar.MILLISECOND, 0)
            val startOfDay = calendar.timeInMillis
            val endOfDay = System.currentTimeMillis()

            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startOfDay,
                endOfDay
            )

            val appStats = stats.find { it.packageName == packageName }
            val totalTimeMs = appStats?.totalTimeInForeground ?: 0

            (totalTimeMs / 60000).toInt()

        } catch (e: Exception) {
            Log.e(TAG, "Error getting usage stats for $packageName", e)
            0
        }
    }

    /**
     * Get usage for time range in minutes
     */
    @RequiresPermission(Manifest.permission.PACKAGE_USAGE_STATS)
    fun getUsageMinutes(
        context: Context,
        packageName: String,
        startTime: Long,
        endTime: Long
    ): Int {
        return try {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startTime,
                endTime
            )

            val appStats = stats.find { it.packageName == packageName }
            val totalTimeMs = appStats?.totalTimeInForeground ?: 0

            (totalTimeMs / 60000).toInt()

        } catch (e: Exception) {
            Log.e(TAG, "Error getting usage stats", e)
            0
        }
    }

    /**
     * Check if app has usage stats permission
     */
    fun hasUsageStatsPermission(context: Context): Boolean {
        return try {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val time = System.currentTimeMillis()
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                time - 1000 * 10,
                time
            )
            stats.isNotEmpty()
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Check if overlay permission is granted
     */
    fun hasOverlayPermission(context: Context): Boolean {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    /**
     * Check if app is a system app
     */
    fun isSystemApp(context: Context, packageName: String): Boolean {
        return try {
            val pm = context.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Get start of current day timestamp
     */
    fun getStartOfDayTimestamp(): Long {
        val calendar = java.util.Calendar.getInstance()
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)
        calendar.set(java.util.Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }

    /**
     * Get start of current week timestamp
     */
    fun getStartOfWeekTimestamp(): Long {
        val calendar = java.util.Calendar.getInstance()
        calendar.set(java.util.Calendar.DAY_OF_WEEK, calendar.firstDayOfWeek)
        calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
        calendar.set(java.util.Calendar.MINUTE, 0)
        calendar.set(java.util.Calendar.SECOND, 0)
        calendar.set(java.util.Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }

    /**
     * Format milliseconds to human-readable time
     */
    fun formatTime(milliseconds: Long): String {
        val hours = (milliseconds / (1000 * 60 * 60)).toInt()
        val minutes = ((milliseconds % (1000 * 60 * 60)) / (1000 * 60)).toInt()

        return when {
            hours > 0 -> "${hours}h ${minutes}m"
            minutes > 0 -> "${minutes}m"
            else -> "< 1m"
        }
    }

    /**
     * Format minutes to human-readable time
     */
    fun formatMinutes(minutes: Int): String {
        val hours = minutes / 60
        val mins = minutes % 60

        return when {
            hours > 0 -> "${hours}h ${mins}m"
            mins > 0 -> "${mins}m"
            else -> "< 1m"
        }
    }
}