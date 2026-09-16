package com.example.pace.managers

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * ShortFormBlockManager - Manages short-form content blocking
 * 
 * This manager handles blocking of short-form content like:
 * - YouTube Shorts
 * - Instagram Reels
 * - Facebook Reels
 * - Snapchat Stories
 * - TikTok Videos
 * 
 * Blocking is implemented via:
 * 1. LockInAccessibilityService - to detect and close short-form content
 * 2. Deep link interception - to prevent opening specific content types
 */
class ShortFormBlockManager private constructor(private val context: Context) {
    
    companion object {
        private const val TAG = "ShortFormBlockManager"
        private const val PREFS_NAME = "shortform_blocks"
        private const val KEY_BLOCKED_PLATFORMS = "blocked_platforms"
        
        // Platform identifiers
        const val YOUTUBE_SHORTS = "youtube_shorts"
        const val INSTAGRAM_REELS = "instagram_reels"
        const val FACEBOOK_REELS = "facebook_reels"
        const val SNAPCHAT_STORIES = "snapchat_stories"
        const val TIKTOK_VIDEOS = "tiktok_videos"
        
        // Package names for detection
        private val PLATFORM_PACKAGES = mapOf(
            YOUTUBE_SHORTS to "com.google.android.youtube",
            INSTAGRAM_REELS to "com.instagram.android",
            FACEBOOK_REELS to "com.facebook.katana",
            SNAPCHAT_STORIES to "com.snapchat.android",
            TIKTOK_VIDEOS to "com.zhiliaoapp.musically"
        )
        
        // URL patterns for detection
        private val PLATFORM_URL_PATTERNS = mapOf(
            YOUTUBE_SHORTS to listOf("youtube.com/shorts", "youtu.be/shorts"),
            INSTAGRAM_REELS to listOf("instagram.com/reel", "instagram.com/reels"),
            FACEBOOK_REELS to listOf("facebook.com/reel", "fb.watch/reel"),
            SNAPCHAT_STORIES to listOf("snapchat.com/story", "snapchat.com/stories"),
            TIKTOK_VIDEOS to listOf("tiktok.com/@", "vm.tiktok.com")
        )
        
        @Volatile
        private var instance: ShortFormBlockManager? = null
        
        fun getInstance(context: Context): ShortFormBlockManager {
            return instance ?: synchronized(this) {
                instance ?: ShortFormBlockManager(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }
    
    data class ShortFormBlock(
        val platform: String,
        val feature: String,
        val isBlocked: Boolean = false
    ) {
        fun getKey(): String = "${platform.lowercase()}_${feature.lowercase()}"
    }
    
    private val prefs: SharedPreferences = 
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    
    private var blockedPlatforms: MutableMap<String, ShortFormBlock> = mutableMapOf()
    
    init {
        loadBlockedPlatforms()
    }
    
    /**
     * Load blocked platforms from SharedPreferences
     */
    private fun loadBlockedPlatforms() {
        try {
            val jsonString = prefs.getString(KEY_BLOCKED_PLATFORMS, "[]")
            val jsonArray = JSONArray(jsonString)
            
            blockedPlatforms.clear()
            for (i in 0 until jsonArray.length()) {
                val jsonObj = jsonArray.getJSONObject(i)
                val block = ShortFormBlock(
                    platform = jsonObj.getString("platform"),
                    feature = jsonObj.getString("feature"),
                    isBlocked = jsonObj.getBoolean("isBlocked")
                )
                blockedPlatforms[block.getKey()] = block
            }
            
            Log.i(TAG, "Loaded ${blockedPlatforms.size} short-form blocks")
        } catch (e: Exception) {
            Log.e(TAG, "Error loading blocked platforms", e)
            blockedPlatforms.clear()
        }
    }
    
    /**
     * Save blocked platforms to SharedPreferences
     */
    private fun saveBlockedPlatforms() {
        try {
            val jsonArray = JSONArray()
            blockedPlatforms.values.forEach { block ->
                val jsonObj = JSONObject().apply {
                    put("platform", block.platform)
                    put("feature", block.feature)
                    put("isBlocked", block.isBlocked)
                }
                jsonArray.put(jsonObj)
            }
            
            prefs.edit()
                .putString(KEY_BLOCKED_PLATFORMS, jsonArray.toString())
                .apply()
            
            Log.i(TAG, "Saved ${blockedPlatforms.size} short-form blocks")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving blocked platforms", e)
        }
    }
    
    /**
     * Set a short-form block
     */
    fun setShortFormBlock(platform: String, feature: String, isBlocked: Boolean) {
        val block = ShortFormBlock(platform, feature, isBlocked)
        blockedPlatforms[block.getKey()] = block
        saveBlockedPlatforms()
        Log.i(TAG, "Set short-form block: ${block.getKey()} = $isBlocked")
    }
    
    /**
     * Check if a platform is blocked
     */
    fun isPlatformBlocked(platform: String, feature: String): Boolean {
        val key = "${platform.lowercase()}_${feature.lowercase()}"
        return blockedPlatforms[key]?.isBlocked ?: false
    }
    
    /**
     * Check if YouTube Shorts is blocked
     */
    fun isYoutubeShortsBlocked(): Boolean {
        return isPlatformBlocked("YouTube", "Shorts")
    }
    
    /**
     * Check if Instagram Reels is blocked
     */
    fun isInstagramReelsBlocked(): Boolean {
        return isPlatformBlocked("Instagram", "Reels")
    }
    
    /**
     * Check if Facebook Reels is blocked
     */
    fun isFacebookReelsBlocked(): Boolean {
        return isPlatformBlocked("Facebook", "Reels")
    }
    
    /**
     * Check if Snapchat Stories is blocked
     */
    fun isSnapchatStoriesBlocked(): Boolean {
        return isPlatformBlocked("Snapchat", "Stories")
    }
    
    /**
     * Check if TikTok is blocked
     */
    fun isTikTokBlocked(): Boolean {
        return isPlatformBlocked("TikTok", "Videos")
    }
    
    /**
     * Check if a package name corresponds to a blocked short-form platform
     */
    fun isPackageBlocked(packageName: String): Boolean {
        return when (packageName) {
            PLATFORM_PACKAGES[YOUTUBE_SHORTS] -> isYoutubeShortsBlocked()
            PLATFORM_PACKAGES[INSTAGRAM_REELS] -> isInstagramReelsBlocked()
            PLATFORM_PACKAGES[FACEBOOK_REELS] -> isFacebookReelsBlocked()
            PLATFORM_PACKAGES[SNAPCHAT_STORIES] -> isSnapchatStoriesBlocked()
            PLATFORM_PACKAGES[TIKTOK_VIDEOS] -> isTikTokBlocked()
            else -> false
        }
    }
    
    /**
     * Check if a URL corresponds to blocked short-form content
     */
    fun isUrlBlocked(url: String): Boolean {
        val normalizedUrl = url.lowercase()
        
        return PLATFORM_URL_PATTERNS.any { (platformKey, patterns) ->
            val isBlocked = when (platformKey) {
                YOUTUBE_SHORTS -> isYoutubeShortsBlocked()
                INSTAGRAM_REELS -> isInstagramReelsBlocked()
                FACEBOOK_REELS -> isFacebookReelsBlocked()
                SNAPCHAT_STORIES -> isSnapchatStoriesBlocked()
                TIKTOK_VIDEOS -> isTikTokBlocked()
                else -> false
            }
            
            isBlocked && patterns.any { pattern -> normalizedUrl.contains(pattern) }
        }
    }
    
    /**
     * Get all short-form blocks
     */
    fun getAllBlocks(): List<ShortFormBlock> {
        return blockedPlatforms.values.toList()
    }
    
    /**
     * Get only active blocks
     */
    fun getActiveBlocks(): List<ShortFormBlock> {
        return blockedPlatforms.values.filter { it.isBlocked }
    }
    
    /**
     * Clear all blocks
     */
    fun clearAllBlocks() {
        blockedPlatforms.clear()
        saveBlockedPlatforms()
        Log.i(TAG, "Cleared all short-form blocks")
    }
    
    /**
     * Get package name for a platform
     */
    fun getPackageForPlatform(platform: String, feature: String): String? {
        val key = "${platform.lowercase()}_${feature.lowercase()}"
        return PLATFORM_PACKAGES[key]
    }
    
    /**
     * Get readable message for blocked short-form content
     */
    fun getBlockMessage(platform: String, feature: String): String {
        return "🚫 $platform $feature is blocked. Focus on what matters!"
    }
}
