package com.example.pace.services.limits

import android.app.usage.UsageStatsManager
import android.content.Context
import android.util.Log
import java.util.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks app usage and enforces daily limits
 * Uses UsageStatsManager for historical usage + session tracking for current usage
 */
class AppLimitTracker(private val context: Context) {
    
    companion object {
        private const val TAG = "AppLimitTracker"
    }
    
    private val usageStatsManager: UsageStatsManager =
        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    
    // Current active sessions: package -> session start time
    private val sessionStart: ConcurrentHashMap<String, Long> = ConcurrentHashMap()
    
    // Current foreground package
    private var currentPackage: String? = null
    
    // Current day of year for detecting day changes
    private var currentDay: Int = getDayOfYear()
    
    /**
     * Called when a new app comes to foreground
     * Handles app switching and session tracking
     */
    fun onAppSwitched(newPackage: String): Boolean {
        // Check for day change
        val today = getDayOfYear()
        if (today != currentDay) {
            Log.d(TAG, "Day changed, resetting sessions")
            sessionStart.clear()
            currentDay = today
        }
        
        // Only track packages with limits
        if (!LockInNativeLimitsHolder.hasLimit(newPackage)) {
            // End current session if any
            currentPackage?.let { endSession(it) }
            currentPackage = null
            Log.d(TAG, "  ➡️ No limit set for $newPackage, skipping tracking")
            return false
        }
        
        Log.d(TAG, "  ➡️ $newPackage HAS a limit set, tracking...")
        
        // Handle app switch
        if (newPackage != currentPackage) {
            currentPackage?.let { endSession(it) }
            currentPackage = newPackage
            startSession(newPackage)
        }
        
        // Check if limit exceeded
        return checkLimit(newPackage)
    }
    
    /**
     * Start a new session for a package
     */
    private fun startSession(packageName: String) {
        val now = System.currentTimeMillis()
        sessionStart[packageName] = now
        Log.d(TAG, "Started session for $packageName at $now")
    }
    
    /**
     * End session for a package
     */
    private fun endSession(packageName: String) {
        val start = sessionStart[packageName] ?: return
        val now = System.currentTimeMillis()
        val deltaMs = now - start
        sessionStart.remove(packageName)
        Log.d(TAG, "Ended session for $packageName: ${deltaMs / 1000}s")
    }
    
    /**
     * Get total usage today for a package (historical + current session)
     * @return usage in milliseconds
     */
    fun getTodayUsageMs(packageName: String): Long {
        val historical = getHistoricalUsageMs(packageName)
        val currentSession = getCurrentSessionMs(packageName)
        val total = historical + currentSession
        
        Log.d(TAG, "Usage for $packageName: historical=${historical/1000}s, session=${currentSession/1000}s, total=${total/1000}s")
        return total
    }
    
    /**
     * Get historical usage from UsageStatsManager (excludes current session)
     */
    private fun getHistoricalUsageMs(packageName: String): Long {
        try {
            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val startOfDay = calendar.timeInMillis
            val now = System.currentTimeMillis()
            
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startOfDay,
                now
            ) ?: return 0L
            
            val stat = stats.firstOrNull { it.packageName == packageName }
            return stat?.totalTimeInForeground ?: 0L
        } catch (e: Exception) {
            Log.e(TAG, "Error getting historical usage: ${e.message}")
            return 0L
        }
    }
    
    /**
     * Get current session usage (time since session started)
     */
    private fun getCurrentSessionMs(packageName: String): Long {
        val start = sessionStart[packageName] ?: return 0L
        val now = System.currentTimeMillis()
        return now - start
    }
    
    /**
     * Check if limit is exceeded for a package
     * @return true if limit exceeded, false otherwise
     */
    fun checkLimit(packageName: String): Boolean {
        val limitMs = LockInNativeLimitsHolder.getLimitMs(packageName)
        
        Log.d(TAG, "🔍 checkLimit for $packageName - limitMs: $limitMs")
        
        if (limitMs == null || limitMs <= 0) {
            Log.d(TAG, "  ➡️ No limit set, returning false")
            return false
        }
        
        val totalUsageMs = getTodayUsageMs(packageName)
        Log.d(TAG, "  ➡️ Total usage: ${totalUsageMs}ms (${totalUsageMs/60000}min), Limit: ${limitMs}ms (${limitMs/60000}min)")
        
        val exceeded = totalUsageMs >= limitMs
        
        if (exceeded) {
            Log.w(TAG, "  🚫 LIMIT EXCEEDED! Usage: ${totalUsageMs/60000}min >= Limit: ${limitMs/60000}min")
        } else {
            val percentUsed = (totalUsageMs.toDouble() / limitMs.toDouble()) * 100
            Log.d(TAG, "  ✅ Under limit - ${"%.1f".format(percentUsed)}% used")
        }
        
        return exceeded
    }
    
    /**
     * Get usage statistics for a package
     * @return map with usageMs, limitMs, remainingMs, percentUsed
     */
    fun getUsageStats(packageName: String): Map<String, Any> {
        val limitMs = LockInNativeLimitsHolder.getLimitMs(packageName) ?: 0L
        val usageMs = getTodayUsageMs(packageName)
        val remainingMs = (limitMs - usageMs).coerceAtLeast(0L)
        val percentUsed = if (limitMs > 0) (usageMs.toDouble() / limitMs * 100).toInt() else 0
        
        return mapOf(
            "packageName" to packageName,
            "usageMs" to usageMs,
            "usageMinutes" to (usageMs / 60000).toInt(),
            "limitMs" to limitMs,
            "limitMinutes" to (limitMs / 60000).toInt(),
            "remainingMs" to remainingMs,
            "remainingMinutes" to (remainingMs / 60000).toInt(),
            "percentUsed" to percentUsed,
            "exceeded" to (usageMs >= limitMs)
        )
    }
    
    /**
     * Get usage stats for all packages with limits
     */
    fun getAllUsageStats(): Map<String, Map<String, Any>> {
        val result = mutableMapOf<String, Map<String, Any>>()
        LockInNativeLimitsHolder.getAllPackagesWithLimits().forEach { packageName ->
            result[packageName] = getUsageStats(packageName)
        }
        return result
    }
    
    /**
     * Force check limits for all tracked packages
     * @return list of packages that exceeded limits
     */
    fun forceCheckAllLimits(): List<String> {
        val exceeded = mutableListOf<String>()
        LockInNativeLimitsHolder.getAllPackagesWithLimits().forEach { packageName ->
            if (checkLimit(packageName)) {
                exceeded.add(packageName)
            }
        }
        return exceeded
    }
    
    /**
     * Clean up - end current session
     */
    fun cleanup() {
        currentPackage?.let { endSession(it) }
        currentPackage = null
    }
    
    /**
     * Get current day of year
     */
    private fun getDayOfYear(): Int {
        return Calendar.getInstance().get(Calendar.DAY_OF_YEAR)
    }
}
