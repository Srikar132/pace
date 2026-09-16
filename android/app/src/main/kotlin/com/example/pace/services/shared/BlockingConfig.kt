package com.example.pace.services.shared

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * BlockingConfig - Centralized configuration storage for all blocking types
 *
 * RESPONSIBILITIES:
 * - Store and retrieve blocking configurations
 * - Manage persistent blocking settings
 * - Provide clean API for all services
 *
 * CONFIGURATIONS:
 * - Persistent blocked apps (always-on)
 * - Persistent blocked websites (always-on)
 * - Short-form blocking settings (always-on)
 * - Notification blocking settings (always-on)
 * - App limits (always-on)
 */
class BlockingConfig private constructor(private val context: Context) {

    companion object {
        private const val TAG = "BlockingConfig"
        private const val PREFS_NAME = "blocking_config"

        // Persistent blocking keys
        private const val KEY_PERSISTENT_APP_BLOCKING = "persistent_app_blocking"
        private const val KEY_PERSISTENT_BLOCKED_APPS = "persistent_blocked_apps"

        private const val KEY_PERSISTENT_WEBSITE_BLOCKING = "persistent_website_blocking"
        private const val KEY_PERSISTENT_BLOCKED_WEBSITES = "persistent_blocked_websites"

        private const val KEY_PERSISTENT_SHORT_FORM_BLOCKING = "persistent_short_form_blocking"
        private const val KEY_PERSISTENT_SHORT_FORM_CONFIG = "persistent_short_form_config"

        private const val KEY_PERSISTENT_NOTIFICATION_BLOCKING = "persistent_notification_blocking"
        private const val KEY_PERSISTENT_NOTIFICATION_CONFIG = "persistent_notification_config"

        @Volatile
        private var INSTANCE: BlockingConfig? = null

        fun getInstance(context: Context): BlockingConfig {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: BlockingConfig(context.applicationContext).also {
                    INSTANCE = it
                }
            }
        }
    }

    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // ==========================================
    // PERSISTENT APP BLOCKING
    // ==========================================

    fun setPersistentAppBlocking(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_PERSISTENT_APP_BLOCKING, enabled).apply()
        Log.d(TAG, "Persistent app blocking: $enabled")
    }

    fun isPersistentAppBlockingEnabled(): Boolean {
        return prefs.getBoolean(KEY_PERSISTENT_APP_BLOCKING, false)
    }

    fun setPersistentBlockedApps(packageNames: List<String>) {
        val jsonArray = JSONArray(packageNames)
        prefs.edit().putString(KEY_PERSISTENT_BLOCKED_APPS, jsonArray.toString()).apply()
        Log.d(TAG, "Persistent blocked apps updated: ${packageNames.size} apps")
    }

    fun getPersistentBlockedApps(): List<String> {
        val json = prefs.getString(KEY_PERSISTENT_BLOCKED_APPS, null) ?: return emptyList()
        return try {
            val jsonArray = JSONArray(json)
            List(jsonArray.length()) { jsonArray.getString(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing blocked apps", e)
            emptyList()
        }
    }

    // ==========================================
    // PERSISTENT WEBSITE BLOCKING
    // ==========================================

    fun setPersistentWebsiteBlocking(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_PERSISTENT_WEBSITE_BLOCKING, enabled).apply()
        Log.d(TAG, "Persistent website blocking: $enabled")
    }

    fun isPersistentWebsiteBlockingEnabled(): Boolean {
        return prefs.getBoolean(KEY_PERSISTENT_WEBSITE_BLOCKING, false)
    }

    fun setPersistentBlockedWebsites(websites: List<Map<String, Any>>) {
        val jsonArray = JSONArray()
        websites.forEach { website ->
            val jsonObject = JSONObject(website)
            jsonArray.put(jsonObject)
        }
        prefs.edit().putString(KEY_PERSISTENT_BLOCKED_WEBSITES, jsonArray.toString()).apply()
        Log.d(TAG, "Persistent blocked websites updated: ${websites.size} websites")
    }

    fun getPersistentBlockedWebsites(): List<Map<String, Any>> {
        val json = prefs.getString(KEY_PERSISTENT_BLOCKED_WEBSITES, null) ?: return emptyList()
        return try {
            val jsonArray = JSONArray(json)
            List(jsonArray.length()) {
                val jsonObject = jsonArray.getJSONObject(it)
                jsonObject.toMap()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing blocked websites", e)
            emptyList()
        }
    }

    // ==========================================
    // SHORT-FORM BLOCKING
    // ==========================================

    fun setPersistentShortFormBlocking(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_PERSISTENT_SHORT_FORM_BLOCKING, enabled).apply()
        Log.d(TAG, "Persistent short-form blocking: $enabled")
    }

    fun isPersistentShortFormBlockingEnabled(): Boolean {
        return prefs.getBoolean(KEY_PERSISTENT_SHORT_FORM_BLOCKING, false)
    }

    fun setPersistentShortFormConfig(config: Map<String, Any>) {
        val jsonObject = JSONObject(config)
        prefs.edit().putString(KEY_PERSISTENT_SHORT_FORM_CONFIG, jsonObject.toString()).apply()
        Log.d(TAG, "Persistent short-form config updated")
    }

    fun getPersistentShortFormConfig(): Map<String, Any> {
        val json = prefs.getString(KEY_PERSISTENT_SHORT_FORM_CONFIG, null) ?: return emptyMap()
        return try {
            JSONObject(json).toMap()
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing short-form config", e)
            emptyMap()
        }
    }

    // ==========================================
    // NOTIFICATION BLOCKING
    // ==========================================

    fun setPersistentNotificationBlocking(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_PERSISTENT_NOTIFICATION_BLOCKING, enabled).apply()
        Log.d(TAG, "Persistent notification blocking: $enabled")
    }

    fun isPersistentNotificationBlockingEnabled(): Boolean {
        return prefs.getBoolean(KEY_PERSISTENT_NOTIFICATION_BLOCKING, false)
    }

    fun setPersistentNotificationConfig(config: Map<String, Any>) {
        val jsonObject = JSONObject(config)
        prefs.edit().putString(KEY_PERSISTENT_NOTIFICATION_CONFIG, jsonObject.toString()).apply()
        Log.d(TAG, "Persistent notification config updated")
    }

    fun getPersistentNotificationConfig(): Map<String, Any> {
        val json = prefs.getString(KEY_PERSISTENT_NOTIFICATION_CONFIG, null) ?: return emptyMap()
        return try {
            JSONObject(json).toMap()
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing notification config", e)
            emptyMap()
        }
    }

    // ==========================================
    // UTILITIES
    // ==========================================

    fun clearAllConfigs() {
        prefs.edit().clear().apply()
        Log.d(TAG, "All blocking configs cleared")
    }

    fun hasAnyBlockingEnabled(): Boolean {
        return isPersistentAppBlockingEnabled() ||
                isPersistentWebsiteBlockingEnabled() ||
                isPersistentShortFormBlockingEnabled() ||
                isPersistentNotificationBlockingEnabled()
    }
}

// Helper extension
private fun JSONObject.toMap(): Map<String, Any> {
    val map = mutableMapOf<String, Any>()
    keys().forEach { key ->
        val value = get(key)
        map[key] = value
    }
    return map
}