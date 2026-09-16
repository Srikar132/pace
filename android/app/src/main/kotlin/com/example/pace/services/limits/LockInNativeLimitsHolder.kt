package com.example.pace.services.limits

import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * Singleton holder for app limits, accessible from both MainActivity and AccessibilityService
 * Thread-safe storage for daily usage limits per package
 */
object LockInNativeLimitsHolder {
    private const val TAG = "LockInNativeLimitsHolder"
    
    // Package name -> daily limit in milliseconds
    val dailyLimits: ConcurrentHashMap<String, Long> = ConcurrentHashMap()
    
    /**
     * Update limits from Flutter
     * @param limitsMap Map of package names to limit minutes
     */
    fun updateLimits(limitsMap: Map<String, Int>) {
        Log.d(TAG, "🔄 updateLimits called - clearing old limits and setting ${limitsMap.size} new limits")
        dailyLimits.clear()
        limitsMap.forEach { (packageName, limitMinutes) ->
            val limitMs = limitMinutes * 60_000L
            dailyLimits[packageName] = limitMs
            Log.d(TAG, "  ✅ Set limit for $packageName: $limitMinutes minutes ($limitMs ms)")
        }
        Log.i(TAG, "✅ Updated ${dailyLimits.size} app limits - Current limits: ${dailyLimits.keys}")
    }
    
    /**
     * Get limit for a specific package
     * @return limit in milliseconds, or null if no limit set
     */
    fun getLimitMs(packageName: String): Long? {
        return dailyLimits[packageName]
    }
    
    /**
     * Check if package has a limit
     */
    fun hasLimit(packageName: String): Boolean {
        return dailyLimits.containsKey(packageName)
    }
    
    /**
     * Remove limit for a package
     */
    fun removeLimit(packageName: String) {
        dailyLimits.remove(packageName)
        Log.d(TAG, "Removed limit for $packageName")
    }
    
    /**
     * Clear all limits
     */
    fun clearAllLimits() {
        dailyLimits.clear()
        Log.d(TAG, "Cleared all limits")
    }
    
    /**
     * Get all packages with limits
     */
    fun getAllPackagesWithLimits(): Set<String> {
        return dailyLimits.keys.toSet()
    }
}
