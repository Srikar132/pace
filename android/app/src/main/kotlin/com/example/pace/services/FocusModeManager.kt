package com.lockin.focus

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.example.pace.models.FocusSession
import com.example.pace.models.Interruption
import com.example.pace.services.AppMonitoringService
import com.example.pace.services.PomodoroManager
import com.example.pace.services.notifications.NotificationBlockingService
import com.example.pace.services.shorts.ShortsBlockingService
import com.example.pace.services.web.WebBlockingVPNService
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/**
 * FocusModeManager - Central coordinator for focus sessions ONLY Blocking is now completely
 * separate and works independently
 */
class FocusModeManager(private val context: Context) {

    companion object {
        private const val TAG = "FocusModeManager"
        private const val PREFS_NAME = "focus_mode_prefs"
        private const val KEY_SESSION_DATA = "current_session_data"
        private const val KEY_SESSION_ACTIVE = "session_active"
        private const val KEY_SESSION_START_TIME = "session_start_time"
        private const val KEY_PAUSED_TIME = "paused_time"
        private const val KEY_IS_PAUSED = "is_paused"

        // Persistent blocking keys for each type
        private const val KEY_PERSISTENT_APP_BLOCKING = "persistent_app_blocking"
        private const val KEY_PERSISTENT_BLOCKED_APPS = "persistent_blocked_apps_json"
        private const val KEY_PERSISTENT_WEBSITE_BLOCKING = "persistent_website_blocking"
        private const val KEY_PERSISTENT_BLOCKED_WEBSITES = "persistent_blocked_websites_json"
        private const val KEY_PERSISTENT_SHORT_FORM_BLOCKING = "persistent_short_form_blocking"
        private const val KEY_PERSISTENT_SHORT_FORM_BLOCKS = "persistent_short_form_blocks_json"
        private const val KEY_PERSISTENT_NOTIFICATION_BLOCKING = "persistent_notification_blocking"
        private const val KEY_PERSISTENT_NOTIFICATION_BLOCKS = "persistent_notification_blocks_json"

        @Volatile private var INSTANCE: FocusModeManager? = null

        fun getInstance(context: Context): FocusModeManager {
            return INSTANCE
                ?: synchronized(this) {
                    INSTANCE
                        ?: FocusModeManager(context.applicationContext).also {
                            INSTANCE = it
                        }
                }
        }
    }

    // Core components
    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Session state
    @Volatile private var currentSession: FocusSession? = null
    @Volatile private var sessionStartTime: Long = 0
    @Volatile private var pausedElapsedTime: Long = 0
    @Volatile private var isPaused: Boolean = false
    @Volatile private var isSessionActive: Boolean = false

    // Timer management
    private var timerRunnable: Runnable? = null
    private var pomodoroManager: PomodoroManager? = null

    // Event communication
    private var eventSink: EventChannel.EventSink? = null
    private val eventQueue = ConcurrentHashMap<String, Any>()

    init {
        restoreSessionIfExists()
        // Start monitoring service if any blocking is active
        ensureMonitoringServiceRunning()
    }

    // ====================
    // EVENT CHANNEL MANAGEMENT
    // ====================

    fun setEventSink(eventSink: EventChannel.EventSink?) {
        this.eventSink = eventSink
        // Send queued events
        eventQueue.forEach { (event, data) -> sendEventToFlutter(event, data) }
        eventQueue.clear()
    }

    private fun sendEventToFlutter(event: String, data: Any) {
        try {
            // FIX: Ensure data is properly serialized as Map<String, Any>
            val serializedData =
                when (data) {
                    is Map<*, *> -> {
                        // Convert to proper Map<String, Any>
                        data.entries.associate { it.key.toString() to (it.value ?: "null") }
                    }
                    else -> mapOf("value" to data)
                }

            val eventData =
                mapOf(
                    "event" to event,
                    "data" to serializedData,
                    "timestamp" to System.currentTimeMillis()
                )

            if (eventSink != null) {
                handler.post { eventSink?.success(eventData) }
            } else {
                eventQueue[event] = serializedData
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending event to Flutter: $event", e)
        }
    }

    // ====================
    // SESSION MANAGEMENT
    // ====================

    suspend fun startSession(sessionData: Map<String, Any>): Boolean {
        return withContext(Dispatchers.Main) {
            try {
                Log.d(TAG, "Starting focus session with data: $sessionData")

                // Parse session data with proper type handling
                val session =
                    try {
                        FocusSession.fromMap(sessionData)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error parsing session data", e)
                        return@withContext false
                    }

                // Validate session data
                if (!validateSessionData(session)) {
                    Log.e(TAG, "Invalid session data")
                    return@withContext false
                }

                // CRITICAL FIX 1: Store session BEFORE starting service
                currentSession = session
                sessionStartTime = System.currentTimeMillis()
                pausedElapsedTime = 0
                isPaused = false
                isSessionActive = true

                // CRITICAL FIX 2: Save to preferences IMMEDIATELY
                saveSessionToPreferences(session)

                // CRITICAL FIX 3: Log what we're storing
                Log.d(TAG, "📱 Session stored:")
                Log.d(TAG, "  ├─ sessionId: ${session.sessionId}")
                Log.d(TAG, "  ├─ sessionType: ${session.sessionType}")
                Log.d(TAG, "  ├─ blockedApps.size: ${session.blockedApps.size}")
                Log.d(TAG, "  └─ blockedApps: ${session.blockedApps}")

                // Initialize timer based on session type
                initializeTimer(session)

                // CRITICAL FIX 4: Start monitoring service AFTER session is stored
                Log.d(TAG, "🚀 Starting monitoring service")
                startMonitoringService(session)

                // Verify session is accessible
                val verifySession = getCurrentSession()
                if (verifySession == null) {
                    Log.e(TAG, "⚠️ WARNING: Session not accessible after storage!")
                } else {
                    Log.d(TAG, "✅ Session verification passed")
                }

                // Log current blocking status
                Log.d(TAG, "🔍 Blocking Status:")
                Log.d(TAG, "  ├─ Session Active: $isSessionActive")
                Log.d(TAG, "  ├─ Blocking Active: ${isBlockingActive()}")
                Log.d(TAG, "  ├─ Persistent Blocking: ${isPersistentAppBlockingEnabled()}")
                Log.d(TAG, "  └─ Blocked Apps: ${session.blockedApps.size}")

                // Send start event to Flutter with proper data
                sendEventToFlutter(
                    "session_started",
                    mapOf(
                        "sessionId" to session.sessionId,
                        "sessionType" to session.sessionType,
                        "plannedDuration" to session.plannedDuration,
                        "startTime" to sessionStartTime,
                        "blockedApps" to session.blockedApps
                    )
                )

                Log.d(TAG, "✅ Focus session started successfully: ${session.sessionId}")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Error starting session", e)
                e.printStackTrace()
                false
            }
        }
    }

    suspend fun pauseSession(): Boolean {
        return withContext(Dispatchers.Main) {
            try {
                if (!isSessionActive || isPaused) {
                    Log.w(TAG, "Cannot pause: session not active or already paused")
                    return@withContext false
                }

                Log.d(TAG, "Pausing focus session")

                // Calculate elapsed time
                pausedElapsedTime = System.currentTimeMillis() - sessionStartTime
                isPaused = true

                // Stop timer
                stopTimer()

                // Update preferences
                updateSessionState()

                // Send pause event to Flutter
                sendEventToFlutter(
                    "session_paused",
                    mapOf(
                        "pausedAt" to System.currentTimeMillis(),
                        "elapsedTime" to pausedElapsedTime
                    )
                )

                Log.d(TAG, "Session paused successfully")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Error pausing session", e)
                false
            }
        }
    }

    suspend fun resumeSession(): Boolean {
        return withContext(Dispatchers.Main) {
            try {
                if (!isSessionActive || !isPaused) {
                    Log.w(TAG, "Cannot resume: session not active or not paused")
                    return@withContext false
                }

                Log.d(TAG, "Resuming focus session")

                // Adjust start time to account for paused time
                sessionStartTime = System.currentTimeMillis() - pausedElapsedTime
                isPaused = false

                // Resume timer
                currentSession?.let { initializeTimer(it) }

                // Update preferences
                updateSessionState()

                // Send resume event to Flutter
                sendEventToFlutter(
                    "session_resumed",
                    mapOf(
                        "resumedAt" to System.currentTimeMillis(),
                        "elapsedTime" to pausedElapsedTime
                    )
                )

                Log.d(TAG, "Session resumed successfully")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Error resuming session", e)
                false
            }
        }
    }

    suspend fun endSession(): Boolean {
        return withContext(Dispatchers.Main) {
            try {
                if (!isSessionActive) {
                    Log.w(TAG, "No active session to end")
                    return@withContext false
                }

                Log.d(TAG, "Ending focus session")

                val session = currentSession
                if (session != null) {
                    // Calculate final stats
                    val endTime = System.currentTimeMillis()
                    val totalElapsed =
                        if (isPaused) pausedElapsedTime else endTime - sessionStartTime
                    val actualDuration = (totalElapsed / 60000).toInt() // Convert to minutes
                    val completionRate =
                        if (session.plannedDuration > 0) {
                            (actualDuration.toFloat() / session.plannedDuration) * 100
                        } else 100f

                    // Update session with final data
                    val completedSession =
                        session.copy(
                            endTime = endTime,
                            actualDuration = actualDuration,
                            completionRate = completionRate.coerceAtMost(100f),
                            status =
                                if (completionRate >= 100f) "completed"
                                else "ended_early"
                        )

                    // Stop timer
                    stopTimer()

                    // Clear session data
                    clearSessionFromPreferences()
                    currentSession = null
                    isSessionActive = false
                    isPaused = false

                    // Send completion event to Flutter with proper data structure
                    sendEventToFlutter(
                        "session_completed",
                        mapOf(
                            "sessionId" to completedSession.sessionId,
                            "actualDuration" to actualDuration,
                            "completionRate" to completionRate,
                            "totalElapsed" to totalElapsed,
                            "interruptions" to completedSession.interruptions.size,
                            "status" to completedSession.status
                        )
                    )

                    Log.d(TAG, "Session ended successfully: ${session.sessionId}")
                } else {
                    Log.e(TAG, "Current session is null during end")
                }

                true
            } catch (e: Exception) {
                Log.e(TAG, "Error ending session", e)
                false
            }
        }
    }

    fun getCurrentSessionStatus(): Map<String, Any>? {
        return try {
            val session = currentSession ?: return null

            val elapsed =
                if (isPaused) {
                    pausedElapsedTime
                } else if (isSessionActive) {
                    System.currentTimeMillis() - sessionStartTime
                } else {
                    0L
                }

            mapOf(
                "sessionId" to session.sessionId,
                "isActive" to isSessionActive,
                "isPaused" to isPaused,
                "elapsedTime" to elapsed,
                "elapsedMinutes" to (elapsed / 60000).toInt(),
                "plannedDuration" to session.plannedDuration,
                "sessionType" to session.sessionType,
                "timerMode" to session.timerMode,
                "status" to session.status,
                "completionRate" to
                        if (session.plannedDuration > 0) {
                            ((elapsed / 60000).toInt().toFloat() / session.plannedDuration) *
                                    100
                        } else 0f,
                "remainingTime" to
                        if (session.sessionType == "timer" && session.plannedDuration > 0) {
                            maxOf(0, (session.plannedDuration * 60000) - elapsed)
                        } else 0L
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error getting session status", e)
            null
        }
    }

    // ====================
    // TIMER MANAGEMENT
    // ====================

    private fun initializeTimer(session: FocusSession) {
        stopTimer()

        when (session.sessionType.lowercase()) {
            "timer" -> initializeCountdownTimer(session)
            "stopwatch" -> initializeStopwatchTimer(session)
            "pomodoro" -> initializePomodoroTimer(session)
            else -> initializeStopwatchTimer(session)
        }
    }

    private fun initializeCountdownTimer(session: FocusSession) {
        timerRunnable =
            object : Runnable {
                override fun run() {
                    if (!isPaused && isSessionActive) {
                        val elapsed = System.currentTimeMillis() - sessionStartTime
                        val remaining = (session.plannedDuration * 60000L) - elapsed

                        sendTimerUpdate(elapsed, remaining)

                        if (remaining <= 0) {
                            scope.launch { completeSession("timer_finished") }
                            return
                        }

                        handler.postDelayed(this, 1000)
                    }
                }
            }
        handler.post(timerRunnable!!)
    }

    private fun initializeStopwatchTimer(session: FocusSession) {
        timerRunnable =
            object : Runnable {
                override fun run() {
                    if (!isPaused && isSessionActive) {
                        val elapsed = System.currentTimeMillis() - sessionStartTime
                        sendTimerUpdate(elapsed, 0L)
                        handler.postDelayed(this, 1000)
                    }
                }
            }
        handler.post(timerRunnable!!)
    }

    private fun initializePomodoroTimer(session: FocusSession) {
        pomodoroManager =
            PomodoroManager(session) { phase, elapsed, remaining ->
                sendTimerUpdate(elapsed, remaining, phase)

                if (remaining <= 0) {
                    when (phase) {
                        "work" -> pomodoroManager?.startBreak()
                        "short_break", "long_break" -> pomodoroManager?.startWork()
                    }
                }
            }
        pomodoroManager?.start()
    }

    private fun stopTimer() {
        timerRunnable?.let {
            handler.removeCallbacks(it)
            timerRunnable = null
        }
        pomodoroManager?.stop()
        pomodoroManager = null
    }

    private fun sendTimerUpdate(elapsed: Long, remaining: Long, phase: String = "focus") {
        sendEventToFlutter(
            "timer_update",
            mapOf(
                "elapsed" to elapsed,
                "elapsedMinutes" to (elapsed / 60000).toInt(),
                "remaining" to remaining,
                "remainingMinutes" to (remaining / 60000).toInt(),
                "phase" to phase
            )
        )
    }

    // ====================
    // SERVICE COORDINATION
    // ====================

    private suspend fun startMonitoringService(session: FocusSession) {
        withContext(Dispatchers.IO) {
            try {
                // CRITICAL FIX: Create proper JSON with explicit blockedApps array
                val sessionJson =
                    JSONObject().apply {
                        put("sessionId", session.sessionId)
                        put("userId", session.userId)
                        put("startTime", session.startTime)
                        put("plannedDuration", session.plannedDuration)
                        put("sessionType", session.sessionType)
                        put("timerMode", session.timerMode)
                        put("status", session.status)

                        // CRITICAL: Explicitly create blockedApps array
                        val blockedAppsArray = org.json.JSONArray()
                        session.blockedApps.forEach { app -> blockedAppsArray.put(app) }
                        put("blockedApps", blockedAppsArray)

                        Log.d(
                            TAG,
                            "📱 Created JSON with ${blockedAppsArray.length()} blocked apps"
                        )

                        // Add other arrays
                        val websitesArray = org.json.JSONArray()
                        session.blockedWebsites.forEach { website ->
                            websitesArray.put(JSONObject(website))
                        }
                        put("blockedWebsites", websitesArray)

                        put("shortFormBlocked", session.shortFormBlocked)
                        put("shortFormBlocks", JSONObject(session.shortFormBlocks))
                        put("notificationsBlocked", session.notificationsBlocked)
                        put("notificationBlocks", JSONObject(session.notificationBlocks))
                    }

                val sessionJsonString = sessionJson.toString()
                Log.d(TAG, "📤 Sending to service: $sessionJsonString")

                val monitoringIntent =
                    Intent(context, AppMonitoringService::class.java).apply {
                        action = "START_MONITORING"
                        putExtra("session_data", sessionJsonString)
                    }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(monitoringIntent)
                } else {
                    context.startService(monitoringIntent)
                }

                Log.d(TAG, "✅ Monitoring service start command sent")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting monitoring service", e)
                e.printStackTrace()
            }
        }
    }

    private fun ensureMonitoringServiceRunning() {
        try {
            // Start service if any blocking is active OR session is active
            if (isBlockingActive() || isSessionActive) {
                val intent =
                    Intent(context, AppMonitoringService::class.java).apply {
                        action = AppMonitoringService.ACTION_START_MONITORING
                    }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "Ensured monitoring service is running")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error ensuring monitoring service", e)
        }
    }

    // ====================
    // INTERRUPTION HANDLING
    // ====================

    fun reportInterruption(
        packageName: String,
        appName: String,
        type: String,
        wasBlocked: Boolean
    ) {
        try {
            val session = currentSession

            val interruption =
                Interruption(
                    timestamp = System.currentTimeMillis(),
                    type = type,
                    appPackage = packageName,
                    appName = appName,
                    wasBlocked = wasBlocked
                )

            // Add to session interruptions if session exists
            session?.interruptions?.add(interruption)
            session?.let { saveSessionToPreferences(it) }

            // Send to Flutter
            sendEventToFlutter(
                "interruption_detected",
                mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "type" to type,
                    "wasBlocked" to wasBlocked,
                    "sessionId" to (session?.sessionId ?: ""),
                    "totalInterruptions" to (session?.interruptions?.size ?: 0),
                    "timestamp" to interruption.timestamp
                )
            )

            Log.d(TAG, "Interruption reported: $appName ($type, blocked: $wasBlocked)")
        } catch (e: Exception) {
            Log.e(TAG, "Error reporting interruption", e)
        }
    }

    // ====================
    // UTILITY METHODS
    // ====================

    private suspend fun completeSession(reason: String) {
        try {
            sendEventToFlutter("session_auto_completed", mapOf("reason" to reason))
            endSession()
        } catch (e: Exception) {
            Log.e(TAG, "Error completing session", e)
        }
    }

    private fun validateSessionData(session: FocusSession): Boolean {
        return try {
            session.sessionId.isNotEmpty() &&
                    session.userId.isNotEmpty() &&
                    session.sessionType.isNotEmpty() &&
                    (session.sessionType != "timer" || session.plannedDuration > 0)
        } catch (e: Exception) {
            Log.e(TAG, "Session validation error", e)
            false
        }
    }

    // ====================
    // PERSISTENCE
    // ====================

    private fun saveSessionToPreferences(session: FocusSession) {
        try {
            prefs.edit().apply {
                putString(KEY_SESSION_DATA, JSONObject(session.toMap()).toString())
                putLong(KEY_SESSION_START_TIME, sessionStartTime)
                putLong(KEY_PAUSED_TIME, pausedElapsedTime)
                putBoolean(KEY_IS_PAUSED, isPaused)
                putBoolean(KEY_SESSION_ACTIVE, isSessionActive)
                apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error saving session to preferences", e)
        }
    }

    private fun updateSessionState() {
        try {
            prefs.edit().apply {
                putLong(KEY_SESSION_START_TIME, sessionStartTime)
                putLong(KEY_PAUSED_TIME, pausedElapsedTime)
                putBoolean(KEY_IS_PAUSED, isPaused)
                putBoolean(KEY_SESSION_ACTIVE, isSessionActive)
                apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating session state", e)
        }
    }

    private fun clearSessionFromPreferences() {
        try {
            prefs.edit().apply {
                remove(KEY_SESSION_DATA)
                remove(KEY_SESSION_START_TIME)
                remove(KEY_PAUSED_TIME)
                putBoolean(KEY_IS_PAUSED, false)
                putBoolean(KEY_SESSION_ACTIVE, false)
                apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing session from preferences", e)
        }
    }

    private fun restoreSessionIfExists() {
        try {
            if (prefs.getBoolean(KEY_SESSION_ACTIVE, false)) {
                val sessionJson = prefs.getString(KEY_SESSION_DATA, null)
                if (sessionJson != null) {
                    val sessionData = JSONObject(sessionJson).toMap()
                    currentSession = FocusSession.fromMap(sessionData)
                    sessionStartTime =
                        prefs.getLong(KEY_SESSION_START_TIME, System.currentTimeMillis())
                    pausedElapsedTime = prefs.getLong(KEY_PAUSED_TIME, 0)
                    isPaused = prefs.getBoolean(KEY_IS_PAUSED, false)
                    isSessionActive = true

                    if (!isPaused && currentSession != null) {
                        initializeTimer(currentSession!!)
                    }

                    Log.d(TAG, "Session restored from preferences: ${currentSession?.sessionId}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error restoring session", e)
            clearSessionFromPreferences()
        }
    }

    // Public getters
    fun isSessionActive(): Boolean = isSessionActive
    fun getCurrentSession(): FocusSession? = currentSession
    fun getSessionStartTime(): Long = sessionStartTime
    fun isPaused(): Boolean = isPaused

    // ====================
    // PERSISTENT (ALWAYS-ON) BLOCKING CONTROLS
    // ====================

    fun setPersistentAppBlocking(enabled: Boolean, blockedApps: List<String>? = null) {
        try {
            prefs.edit().apply {
                putBoolean(KEY_PERSISTENT_APP_BLOCKING, enabled)
                if (blockedApps != null) {
                    putString(
                        KEY_PERSISTENT_BLOCKED_APPS,
                        org.json.JSONArray(blockedApps).toString()
                    )
                }
                apply()
            }
            ensureMonitoringServiceRunning()
            Log.d(TAG, "Persistent app blocking ${if (enabled) "enabled" else "disabled"}")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting persistent app blocking", e)
        }
    }

    fun isPersistentAppBlockingEnabled(): Boolean =
        prefs.getBoolean(KEY_PERSISTENT_APP_BLOCKING, false)

    fun getPersistentBlockedApps(): List<String> {
        try {
            val json = prefs.getString(KEY_PERSISTENT_BLOCKED_APPS, "[]") ?: "[]"
            val arr = org.json.JSONArray(json)
            val list = mutableListOf<String>()
            for (i in 0 until arr.length()) list.add(arr.getString(i))
            return list
        } catch (e: Exception) {
            Log.e(TAG, "Error reading persistent blocked apps", e)
            return emptyList()
        }
    }

    fun setPersistentWebsiteBlocking(
        enabled: Boolean,
        blockedWebsites: List<Map<String, Any>>? = null
    ) {
        try {
            prefs.edit().apply {
                putBoolean(KEY_PERSISTENT_WEBSITE_BLOCKING, enabled)
                if (blockedWebsites != null) {
                    val jsonArray = org.json.JSONArray()
                    blockedWebsites.forEach { website ->
                        jsonArray.put(org.json.JSONObject(website))
                    }
                    putString(KEY_PERSISTENT_BLOCKED_WEBSITES, jsonArray.toString())
                }
                apply()
            }
            updateWebBlocking()
            Log.d(TAG, "Persistent website blocking ${if (enabled) "enabled" else "disabled"}")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting persistent website blocking", e)
        }
    }

    fun isPersistentWebsiteBlockingEnabled(): Boolean =
        prefs.getBoolean(KEY_PERSISTENT_WEBSITE_BLOCKING, false)

    fun getPersistentBlockedWebsites(): List<Map<String, Any>> {
        try {
            val json = prefs.getString(KEY_PERSISTENT_BLOCKED_WEBSITES, "[]") ?: "[]"
            val arr = org.json.JSONArray(json)
            val list = mutableListOf<Map<String, Any>>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                list.add(obj.toMap())
            }
            return list
        } catch (e: Exception) {
            Log.e(TAG, "Error reading persistent blocked websites", e)
            return emptyList()
        }
    }

    fun setPersistentShortFormBlocking(
        enabled: Boolean,
        shortFormBlocks: Map<String, Any>? = null
    ) {
        try {
            prefs.edit().apply {
                putBoolean(KEY_PERSISTENT_SHORT_FORM_BLOCKING, enabled)
                if (shortFormBlocks != null) {
                    putString(
                        KEY_PERSISTENT_SHORT_FORM_BLOCKS,
                        org.json.JSONObject(shortFormBlocks).toString()
                    )
                }
                apply()
            }
            updateShortFormBlocking()
            Log.d(TAG, "Persistent short-form blocking ${if (enabled) "enabled" else "disabled"}")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting persistent short-form blocking", e)
        }
    }

    fun isPersistentShortFormBlockingEnabled(): Boolean =
        prefs.getBoolean(KEY_PERSISTENT_SHORT_FORM_BLOCKING, false)

    fun getPersistentShortFormBlocks(): Map<String, Any> {
        try {
            val json = prefs.getString(KEY_PERSISTENT_SHORT_FORM_BLOCKS, "{}") ?: "{}"
            return org.json.JSONObject(json).toMap()
        } catch (e: Exception) {
            Log.e(TAG, "Error reading persistent short-form blocks", e)
            return emptyMap()
        }
    }

    fun setPersistentNotificationBlocking(
        enabled: Boolean,
        notificationBlocks: Map<String, Any>? = null
    ) {
        try {
            prefs.edit().apply {
                putBoolean(KEY_PERSISTENT_NOTIFICATION_BLOCKING, enabled)
                if (notificationBlocks != null) {
                    putString(
                        KEY_PERSISTENT_NOTIFICATION_BLOCKS,
                        org.json.JSONObject(notificationBlocks).toString()
                    )
                }
                apply()
            }
            updateNotificationBlocking()
            Log.d(TAG, "Persistent notification blocking ${if (enabled) "enabled" else "disabled"}")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting persistent notification blocking", e)
        }
    }

    fun isPersistentNotificationBlockingEnabled(): Boolean =
        prefs.getBoolean(KEY_PERSISTENT_NOTIFICATION_BLOCKING, false)

    fun getPersistentNotificationBlocks(): Map<String, Any> {
        try {
            val json = prefs.getString(KEY_PERSISTENT_NOTIFICATION_BLOCKS, "{}") ?: "{}"
            return org.json.JSONObject(json).toMap()
        } catch (e: Exception) {
            Log.e(TAG, "Error reading persistent notification blocks", e)
            return emptyMap()
        }
    }

    private fun updateWebBlocking() {
        try {
            if (isPersistentWebsiteBlockingEnabled()) {
                val websites = getPersistentBlockedWebsites()
                WebBlockingVPNService.updateBlocks(context, websites)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WebBlockingVPNService.startVPN(context, websites)
                }
            } else {
                WebBlockingVPNService.stopVPN(context)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating web blocking", e)
        }
    }

    private fun updateShortFormBlocking() {
        try {
            if (isPersistentShortFormBlockingEnabled()) {
                val blocks = getPersistentShortFormBlocks()
                ShortsBlockingService.updateBlocks(context, blocks)
            } else {
                ShortsBlockingService.updateBlocks(context, emptyMap())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating short-form blocking", e)
        }
    }

    private fun updateNotificationBlocking() {
        try {
            if (isPersistentNotificationBlockingEnabled()) {
                val blocks = getPersistentNotificationBlocks()
                NotificationBlockingService.updateBlocks(context, blocks)
            } else {
                NotificationBlockingService.updateBlocks(context, emptyMap())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating notification blocking", e)
        }
    }

    /** Returns true if any blocking mode should be enforced */
    fun isBlockingActive(): Boolean =
        isSessionActive ||
                isPersistentAppBlockingEnabled() ||
                isPersistentWebsiteBlockingEnabled() ||
                isPersistentShortFormBlockingEnabled() ||
                isPersistentNotificationBlockingEnabled()

    fun isPersistentBlockingEnabled(): Boolean = isPersistentAppBlockingEnabled()

    fun cleanup() {
        scope.cancel()
        stopTimer()
        eventSink = null
        eventQueue.clear()
    }
}

// Extension function to convert JSONObject to Map
private fun JSONObject.toMap(): Map<String, Any> {
    val map = mutableMapOf<String, Any>()
    keys().forEach { key -> map[key] = get(key) }
    return map
}