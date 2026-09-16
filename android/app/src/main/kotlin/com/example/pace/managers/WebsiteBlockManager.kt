package com.example.pace.managers

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * WebsiteBlockManager - Manages blocked websites
 * 
 * This manager handles website blocking configuration.
 * Actual blocking is implemented via:
 * 1. LockInAccessibilityService - for browser URL interception
 * 2. Future VPN service - for system-wide blocking
 */
class WebsiteBlockManager private constructor(private val context: Context) {
    
    companion object {
        private const val TAG = "WebsiteBlockManager"
        private const val PREFS_NAME = "website_blocks"
        private const val KEY_BLOCKED_WEBSITES = "blocked_websites"
        
        @Volatile
        private var instance: WebsiteBlockManager? = null
        
        fun getInstance(context: Context): WebsiteBlockManager {
            return instance ?: synchronized(this) {
                instance ?: WebsiteBlockManager(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }
    
    data class BlockedWebsite(
        val url: String,
        val name: String,
        val isActive: Boolean = true
    )
    
    private val prefs: SharedPreferences = 
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    
    private var blockedWebsites: MutableMap<String, BlockedWebsite> = mutableMapOf()
    
    init {
        loadBlockedWebsites()
    }
    
    /**
     * Load blocked websites from SharedPreferences
     */
    private fun loadBlockedWebsites() {
        try {
            val jsonString = prefs.getString(KEY_BLOCKED_WEBSITES, "[]")
            val jsonArray = JSONArray(jsonString)
            
            blockedWebsites.clear()
            for (i in 0 until jsonArray.length()) {
                val jsonObj = jsonArray.getJSONObject(i)
                val website = BlockedWebsite(
                    url = jsonObj.getString("url"),
                    name = jsonObj.getString("name"),
                    isActive = jsonObj.optBoolean("isActive", true)
                )
                blockedWebsites[website.url] = website
            }
            
            Log.i(TAG, "Loaded ${blockedWebsites.size} blocked websites")
        } catch (e: Exception) {
            Log.e(TAG, "Error loading blocked websites", e)
            blockedWebsites.clear()
        }
    }
    
    /**
     * Save blocked websites to SharedPreferences
     */
    private fun saveBlockedWebsites() {
        try {
            val jsonArray = JSONArray()
            blockedWebsites.values.forEach { website ->
                val jsonObj = JSONObject().apply {
                    put("url", website.url)
                    put("name", website.name)
                    put("isActive", website.isActive)
                }
                jsonArray.put(jsonObj)
            }
            
            prefs.edit()
                .putString(KEY_BLOCKED_WEBSITES, jsonArray.toString())
                .apply()
            
            Log.i(TAG, "Saved ${blockedWebsites.size} blocked websites")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving blocked websites", e)
        }
    }
    
    /**
     * Add or update a blocked website
     */
    fun addBlockedWebsite(url: String, name: String, isActive: Boolean = true) {
        val website = BlockedWebsite(url, name, isActive)
        blockedWebsites[url] = website
        saveBlockedWebsites()
        Log.i(TAG, "Added/Updated blocked website: $url")
    }
    
    /**
     * Remove a blocked website
     */
    fun removeBlockedWebsite(url: String) {
        if (blockedWebsites.remove(url) != null) {
            saveBlockedWebsites()
            Log.i(TAG, "Removed blocked website: $url")
        }
    }
    
    /**
     * Toggle website active status
     */
    fun toggleWebsite(url: String) {
        blockedWebsites[url]?.let { website ->
            val updated = website.copy(isActive = !website.isActive)
            blockedWebsites[url] = updated
            saveBlockedWebsites()
            Log.i(TAG, "Toggled website $url to ${updated.isActive}")
        }
    }
    
    /**
     * Check if a URL should be blocked
     * Returns true if the URL matches any active blocked website
     */
    fun isUrlBlocked(url: String): Boolean {
        val normalizedUrl = normalizeUrl(url)
        Log.d(TAG, "🔍 Checking URL: '$url' -> normalized: '$normalizedUrl'")
        Log.d(TAG, "🔍 Available blocked websites: ${blockedWebsites.size}")
        
        if (blockedWebsites.isEmpty()) {
            Log.w(TAG, "⚠️ No blocked websites configured!")
            return false
        }
        
        val isBlocked = blockedWebsites.values.any { website ->
            val normalizedBlockedUrl = normalizeUrl(website.url)
            Log.d(TAG, "🔍 Comparing with blocked: '${website.url}' -> normalized: '$normalizedBlockedUrl', isActive: ${website.isActive}")
            
            val matches = website.isActive && (
                normalizedUrl.contains(normalizedBlockedUrl) || 
                normalizedBlockedUrl.contains(normalizedUrl)
            )
            
            if (matches) {
                Log.i(TAG, "✅ URL matched blocked website: ${website.name}")
            }
            matches
        }
        
        Log.d(TAG, "🔍 Final result for '$url': blocked = $isBlocked")
        return isBlocked
    }
    
    /**
     * Normalize URL for comparison by removing protocols, www, and trailing slashes
     */
    private fun normalizeUrl(url: String): String {
        return url.lowercase()
            .removePrefix("https://")
            .removePrefix("http://")
            .removePrefix("www.")
            .removeSuffix("/")
            .trim()
    }
    
    /**
     * Get all blocked websites
     */
    fun getBlockedWebsites(): List<BlockedWebsite> {
        return blockedWebsites.values.toList()
    }
    
    /**
     * Get only active blocked websites
     */
    fun getActiveBlockedWebsites(): List<BlockedWebsite> {
        return blockedWebsites.values.filter { it.isActive }
    }
    
    /**
     * Clear all blocked websites
     */
    fun clearAllBlocks() {
        blockedWebsites.clear()
        saveBlockedWebsites()
        Log.i(TAG, "Cleared all blocked websites")
    }
    
    /**
     * Get count of blocked websites
     */
    fun getBlockedWebsitesCount(): Int {
        return blockedWebsites.size
    }
    
    /**
     * Get count of active blocked websites
     */
    fun getActiveBlockedWebsitesCount(): Int {
        return blockedWebsites.values.count { it.isActive }
    }
}
