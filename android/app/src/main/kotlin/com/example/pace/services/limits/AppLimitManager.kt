package com.example.pace.services.limits

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.core.content.edit
import com.example.pace.models.AppLimit
import com.example.pace.models.AppLimitStatus
import com.example.pace.models.AppUsageStats
import com.example.pace.models.LimitStatusType
import com.example.pace.services.FlutterOverlayManager
import com.example.pace.services.NotificationHelper
import com.example.pace.services.UsageTrackingJobService
import com.lockin.focus.FocusModeManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/**
 * AppLimitManager - Manages daily and weekly app usage limits
 * Tracks usage, enforces limits, and provides warnings
 */
class AppLimitManager(private val context: Context) {

    companion object {
        private const val TAG = "AppLimitManager"
        private const val PREFS_NAME = "app_limits"
        private const val USAGE_TRACKING_JOB_ID = 2001

        // Warning thresholds
        private const val WARNING_THRESHOLD_75 = 75
        private const val WARNING_THRESHOLD_90 = 90
        private const val LIMIT_EXCEEDED_THRESHOLD = 100
    }

    private val prefs:  SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val usageStatsManager = context.getSystemService(Context. USAGE_STATS_SERVICE) as UsageStatsManager
    private val jobScheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
    private val scope = CoroutineScope(Dispatchers. IO + SupervisorJob())

    // Cache for app limits and usage data
    private val appLimits = ConcurrentHashMap<String, AppLimit>()
    private val todayUsageCache = ConcurrentHashMap<String, Long>()
    private val warningsSentToday = ConcurrentHashMap<String, Set<Int>>()

    // Track last scheduling time to prevent too frequent scheduling
    private var lastScheduleTime = 0L
    private val MIN_SCHEDULE_INTERVAL = 60000L // 1 minute minimum between scheduling attempts

    init {
        loadAppLimitsFromPrefs()
        loadWarningsFromPrefs()

        // Only schedule tracking if we actually have app limits
        if (appLimits.isNotEmpty()) {
            Log.d(TAG, "AppLimitManager initialized with ${appLimits.size} app limits")
            scheduleUsageTrackingIfNeeded()
        } else {
            Log.d(TAG, "AppLimitManager initialized but no app limits found - not scheduling usage tracking")
        }
    }

    // ====================
    // APP LIMIT MANAGEMENT
    // ====================

    /**
     * Set app limits from Flutter
     */
    suspend fun setAppLimits(limits: Map<String, Map<String, Any>>): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Setting app limits for ${limits.size} apps")

                appLimits.clear()
                limits.forEach { (packageName, limitData) ->
                    val appLimit = AppLimit.fromMap(limitData)
                    appLimits[packageName] = appLimit
                    Log.d(TAG, "Set limit for $packageName: ${appLimit.dailyLimitMinutes} minutes/day")
                }

                saveAppLimitsToPrefs()

                // Schedule tracking job if we have limits
                if (appLimits.isNotEmpty()) {
                    scheduleUsageTrackingIfNeeded()
                }

                true
            } catch (e: Exception) {
                Log.e(TAG, "Error setting app limits", e)
                false
            }
        }
    }

    /**
     * Get app limit for specific package
     */
    fun getAppLimit(packageName: String): AppLimit? {
        return appLimits[packageName]
    }

    /**
     * Get all app limits
     */
    fun getAllAppLimits(): Map<String, AppLimit> {
        return appLimits. toMap()
    }

    /**
     * Remove app limit
     */
    suspend fun removeAppLimit(packageName: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                appLimits.remove(packageName)
                warningsSentToday.remove(packageName)
                saveAppLimitsToPrefs()
                saveWarningsToPrefs()
                Log.d(TAG, "Removed app limit for $packageName")
                true
            } catch (e:  Exception) {
                Log.e(TAG, "Error removing app limit for $packageName", e)
                false
            }
        }
    }

    // ====================
    // USAGE TRACKING
    // ====================

    /**
     * Check app limits for all apps with limits set
     */
    suspend fun checkAllAppLimits(): List<AppLimitStatus> {
        return withContext(Dispatchers.IO) {
            try {
                val results = mutableListOf<AppLimitStatus>()

                appLimits.forEach { (packageName, limit) ->
                    if (limit.isActive) {
                        val status = checkAppLimit(packageName, limit)
                        results.add(status)

                        // Handle limit enforcement
                        handleLimitStatus(status)
                    }
                }

                Log.d(TAG, "Checked limits for ${results.size} apps")
                results
            } catch (e: Exception) {
                Log.e(TAG, "Error checking app limits", e)
                emptyList()
            }
        }
    }

    /**
     * Check limit for specific app
     */
    private fun checkAppLimit(packageName:  String, limit: AppLimit): AppLimitStatus {
        return try {
            val todayUsageMs = getTodayUsageForApp(packageName)
            val todayUsageMinutes = (todayUsageMs / 60000).toInt()

            val percentageUsed = if (limit.dailyLimitMinutes > 0) {
                (todayUsageMinutes. toFloat() / limit.dailyLimitMinutes * 100).toInt()
            } else {
                0
            }

            val status = when {
                percentageUsed >= LIMIT_EXCEEDED_THRESHOLD -> LimitStatusType.EXCEEDED
                percentageUsed >= WARNING_THRESHOLD_90 -> LimitStatusType.WARNING_90
                percentageUsed >= WARNING_THRESHOLD_75 -> LimitStatusType.WARNING_75
                else -> LimitStatusType.OK
            }

            AppLimitStatus(
                packageName = packageName,
                appName = getAppName(packageName),
                usedMinutes = todayUsageMinutes,
                limitMinutes = limit.dailyLimitMinutes,
                percentageUsed = percentageUsed,
                status = status,
                actionOnExceed = limit.actionOnExceed,
                timeUntilReset = getTimeUntilMidnight()
            )

        } catch (e: Exception) {
            Log.e(TAG, "Error checking limit for $packageName", e)
            AppLimitStatus(
                packageName = packageName,
                appName = getAppName(packageName),
                usedMinutes = 0,
                limitMinutes = limit.dailyLimitMinutes,
                percentageUsed = 0,
                status = LimitStatusType.ERROR,
                actionOnExceed = limit.actionOnExceed,
                timeUntilReset = getTimeUntilMidnight()
            )
        }
    }

    /**
     * Handle limit status (send notifications, block apps, etc.)
     */
    private suspend fun handleLimitStatus(status:  AppLimitStatus) {
        withContext(Dispatchers.Main) {
            try {
                val packageName = status.packageName
                val warningsSent = warningsSentToday[packageName] ?: emptySet()

                when (status.status) {
                    LimitStatusType.WARNING_75 -> {
                        if (! warningsSent.contains(75)) {
                            sendLimitWarningNotification(status, "75%")
                            markWarningSent(packageName, 75)
                        }
                    }

                    LimitStatusType.WARNING_90 -> {
                        if (!warningsSent.contains(90)) {
                            sendLimitWarningNotification(status, "90%")
                            markWarningSent(packageName, 90)
                        }
                    }

                    LimitStatusType.EXCEEDED -> {
                        if (!warningsSent.contains(100)) {
                            handleLimitExceeded(status)
                            markWarningSent(packageName, 100)
                        }
                    }

                    else -> {
                        // No action needed
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "Error handling limit status for ${status.packageName}", e)
            }
        }
    }

    /**
     * Handle when app limit is exceeded
     */
    private suspend fun handleLimitExceeded(status: AppLimitStatus) {
        try {
            Log.d(TAG, "App limit exceeded for ${status.appName}:  ${status.usedMinutes}/${status.limitMinutes} minutes")

            when (status.actionOnExceed) {
                "block" -> {
                    // Add to blocked apps for current session
                    addToBlockedApps(status.packageName)

                    // Show limit exceeded overlay
                    FlutterOverlayManager.showAppLimitOverlay(
                        context = context,
                        appName = status.appName,
                        packageName = status.packageName,
                        limitMinutes = status.limitMinutes,
                        usedMinutes = status.usedMinutes,
                        limitType = "daily",
                        timeUntilReset = status.timeUntilReset,
                        allowOverride = false
                    )
                }

                "warn" -> {
                    sendLimitExceededNotification(status)

                    // Show warning overlay (can be dismissed)
                    FlutterOverlayManager.showAppLimitOverlay(
                        context = context,
                        appName = status.appName,
                        packageName = status.packageName,
                        limitMinutes = status.limitMinutes,
                        usedMinutes = status.usedMinutes,
                        limitType = "daily",
                        timeUntilReset = status.timeUntilReset,
                        allowOverride = true
                    )
                }

                "notify" -> {
                    sendLimitExceededNotification(status)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error handling limit exceeded for ${status.packageName}", e)
        }
    }

    // ====================
    // USAGE STATISTICS
    // ====================

    /**
     * Get today's usage for specific app
     */
    private fun getTodayUsageForApp(packageName: String): Long {
        return try {
            // Check cache first
            todayUsageCache[packageName]?.let { cachedUsage ->
                return cachedUsage
            }

            val calendar = Calendar.getInstance().apply {
                set(Calendar. HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            val startTime = calendar.timeInMillis
            val endTime = System.currentTimeMillis()

            val usageStats = usageStatsManager.queryUsageStats(
                UsageStatsManager. INTERVAL_DAILY,
                startTime,
                endTime
            )

            val usage = usageStats?.find { it.packageName == packageName }?.totalTimeInForeground ?: 0L

            // Cache the result
            todayUsageCache[packageName] = usage

            usage
        } catch (e: Exception) {
            Log.e(TAG, "Error getting usage for $packageName", e)
            0L
        }
    }

    /**
     * Get usage statistics for all apps with limits
     */
    suspend fun getAllAppUsageStats(): Map<String, AppUsageStats> {
        return withContext(Dispatchers.IO) {
            try {
                val results = mutableMapOf<String, AppUsageStats>()

                appLimits.keys.forEach { packageName ->
                    val todayUsage = getTodayUsageForApp(packageName)
                    val weeklyUsage = getWeeklyUsageForApp(packageName)

                    results[packageName] = AppUsageStats(
                        packageName = packageName,
                        appName = getAppName(packageName),
                        todayUsageMs = todayUsage,
                        todayUsageMinutes = (todayUsage / 60000).toInt(),
                        weeklyUsageMs = weeklyUsage,
                        weeklyUsageMinutes = (weeklyUsage / 60000).toInt(),
                        lastUsed = getLastUsedTime(packageName)
                    )
                }

                results
            } catch (e: Exception) {
                Log.e(TAG, "Error getting all app usage stats", e)
                emptyMap()
            }
        }
    }

    /**
     * Get weekly usage for specific app
     */
    private fun getWeeklyUsageForApp(packageName: String): Long {
        return try {
            val calendar = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, -7)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            val startTime = calendar. timeInMillis
            val endTime = System.currentTimeMillis()

            val usageStats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_WEEKLY,
                startTime,
                endTime
            )

            usageStats?.find { it.packageName == packageName }?.totalTimeInForeground ?: 0L
        } catch (e: Exception) {
            Log.e(TAG, "Error getting weekly usage for $packageName", e)
            0L
        }
    }

    /**
     * Get last used time for app
     */
    private fun getLastUsedTime(packageName:  String): Long {
        return try {
            val calendar = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, -1)
            }

            val startTime = calendar.timeInMillis
            val endTime = System.currentTimeMillis()

            val usageStats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startTime,
                endTime
            )

            usageStats?.find { it. packageName == packageName }?.lastTimeUsed ?: 0L
        } catch (e: Exception) {
            Log.e(TAG, "Error getting last used time for $packageName", e)
            0L
        }
    }

    // ====================
    // NOTIFICATIONS
    // ====================

    private fun sendLimitWarningNotification(status: AppLimitStatus, percentage: String) {
        try {
            NotificationHelper.showLimitWarning(
                context = context,
                appName = status.appName,
                percentage = percentage,
                limitMinutes = status.limitMinutes,
                usedMinutes = status.usedMinutes
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error sending warning notification", e)
        }
    }

    private fun sendLimitExceededNotification(status: AppLimitStatus) {
        try {
            NotificationHelper.showLimitExceeded(
                context = context,
                appName = status.appName,
                limitMinutes = status. limitMinutes,
                usedMinutes = status.usedMinutes,
                timeUntilReset = status. timeUntilReset
            )
        } catch (e:  Exception) {
            Log.e(TAG, "Error sending limit exceeded notification", e)
        }
    }

    // ====================
    // UTILITY METHODS
    // ====================

    private fun addToBlockedApps(packageName: String) {
        try {
            val focusManager = FocusModeManager.getInstance(context)
            val currentSession = focusManager.getCurrentSession()

            if (currentSession != null) {
                // Add to session blocked apps
                val updatedBlockedApps = currentSession.blockedApps.toMutableList().apply {
                    if (!contains(packageName)) {
                        add(packageName)
                    }
                }

                Log.d(TAG, "Added $packageName to blocked apps for limit enforcement")
            }
        } catch (e:  Exception) {
            Log.e(TAG, "Error adding app to blocked list", e)
        }
    }

    private fun getAppName(packageName: String): String {
        return try {
            val packageManager = context.packageManager
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    private fun getTodayDateString(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
    }

    private fun getTimeUntilMidnight(): Long {
        val now = Calendar.getInstance()
        val midnight = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return midnight.timeInMillis - now.timeInMillis
    }

    private fun markWarningSent(packageName:  String, threshold: Int) {
        val currentWarnings = warningsSentToday[packageName] ?: emptySet()
        warningsSentToday[packageName] = currentWarnings + threshold
        saveWarningsToPrefs()
    }

    // ====================
    // PERSISTENCE
    // ====================

    private fun saveAppLimitsToPrefs() {
        try {
            val limitsJson = JSONObject()
            appLimits.forEach { (packageName, limit) ->
                limitsJson.put(packageName, JSONObject(limit.toMap()))
            }
            prefs.edit {
                putString("app_limits", limitsJson.toString())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error saving app limits to prefs", e)
        }
    }

    private fun loadAppLimitsFromPrefs() {
        try {
            val limitsJson = prefs.getString("app_limits", "{}")
            if (!limitsJson.isNullOrEmpty()) {
                val jsonObject = JSONObject(limitsJson)
                jsonObject.keys().forEach { packageName ->
                    val limitData = jsonObject.getJSONObject(packageName).toMap()
                    appLimits[packageName] = AppLimit.fromMap(limitData)
                }
                Log.d(TAG, "Loaded ${appLimits.size} app limits from preferences")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading app limits from prefs", e)
        }
    }

    private fun saveWarningsToPrefs() {
        try {
            val today = getTodayDateString()
            val warningsJson = JSONObject()
            warningsSentToday. forEach { (packageName, warnings) ->
                warningsJson.put(packageName, JSONObject().apply {
                    put("warnings", warnings. joinToString(","))
                })
            }
            prefs.edit {
                putString("warnings_$today", warningsJson.toString())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error saving warnings to prefs", e)
        }
    }

    private fun loadWarningsFromPrefs() {
        try {
            val today = getTodayDateString()
            val warningsJson = prefs.getString("warnings_$today", "{}")
            if (!warningsJson.isNullOrEmpty()) {
                val jsonObject = JSONObject(warningsJson)
                jsonObject.keys().forEach { packageName ->
                    val warningData = jsonObject.getJSONObject(packageName)
                    val warnings = warningData.getString("warnings")
                        .split(",")
                        . mapNotNull { it.toIntOrNull() }
                        .toSet()
                    warningsSentToday[packageName] = warnings
                }
            }
        } catch (e:  Exception) {
            Log.e(TAG, "Error loading warnings from prefs", e)
        }
    }

    // ====================
    // JOB SCHEDULING
    // ====================


    private fun scheduleUsageTrackingIfNeeded() {
        try {
            val currentTime = System.currentTimeMillis()

            // Prevent too frequent scheduling to avoid Android system limits
            if (currentTime - lastScheduleTime < MIN_SCHEDULE_INTERVAL) {
                Log.d(TAG, "Skipping job scheduling - too soon since last attempt")
                return
            }

            // Cancel existing job first to avoid duplicates
            jobScheduler.cancel(USAGE_TRACKING_JOB_ID)

            val jobInfo = JobInfo.Builder(
                USAGE_TRACKING_JOB_ID,
                ComponentName(context, UsageTrackingJobService::class.java)
            )
                .setPersisted(true)
                .setPeriodic(15 * 60 * 1000) // Check every 15 minutes
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_NONE)
                .setRequiresCharging(false)
                .setRequiresDeviceIdle(false)
                .build()

            val result = jobScheduler.schedule(jobInfo)
            lastScheduleTime = currentTime

            Log.d(TAG, "Usage tracking job scheduled: ${result == JobScheduler.RESULT_SUCCESS}")
        } catch (e: Exception) {
            Log.e(TAG, "Error scheduling usage tracking job", e)
        }
    }

    fun cleanup() {
        scope.cancel()
        jobScheduler.cancel(USAGE_TRACKING_JOB_ID)
    }
}

// Extension function for JSONObject to Map conversion
private fun JSONObject.toMap(): Map<String, Any> {
    val map = mutableMapOf<String, Any>()
    keys().forEach { key ->
        map[key] = get(key)
    }
    return map
}