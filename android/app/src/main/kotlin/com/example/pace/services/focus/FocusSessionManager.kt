package com.example.pace.services.focus

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.example.pace.models.FocusSession
import com.example.pace.models.Interruption
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/**
 * FocusSessionManager - PURE session management
 *
 * RESPONSIBILITIES:
 * - Start/Pause/Resume/End sessions
 * - Timer management (countdown, stopwatch, pomodoro)
 * - Session state persistence
 * - Flutter event communication
 *
 * DOES NOT HANDLE:
 * - App blocking (that's FocusMonitoringService)
 * - Persistent blocking (that's BlockingConfigManager)
 * - App limits (that's AppLimitManager)
 */
class FocusSessionManager private constructor(private val context: Context) {

    companion object {
        private const val TAG = "FocusSessionManager"
        private const val PREFS_NAME = "focus_sessions"

        // Preference keys
        private const val KEY_CURRENT_SESSION = "current_session"
        private const val KEY_SESSION_START_TIME = "session_start_time"
        private const val KEY_PAUSED_TIME = "paused_elapsed_time"
        private const val KEY_IS_PAUSED = "is_paused"
        private const val KEY_IS_ACTIVE = "is_active"

        @Volatile
        private var INSTANCE: FocusSessionManager? = null

        fun getInstance(context: Context): FocusSessionManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: FocusSessionManager(context.applicationContext).also {
                    INSTANCE = it
                }
            }
        }
    }

    // Core components
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())

    // Session state
    @Volatile private var currentSession: FocusSession? = null
    @Volatile private var sessionStartTime: Long = 0
    @Volatile private var pausedElapsedTime: Long = 0
    @Volatile private var isPaused: Boolean = false
    @Volatile private var isActive: Boolean = false

    // Timer
    private var timerRunnable: Runnable? = null

    // Flutter communication
    private var eventSink: EventChannel.EventSink? = null
    private val eventQueue = ConcurrentHashMap<String, Any>()

    // Lifecycle callbacks for MainActivity to keep FocusMonitoringService in sync,
    // fired regardless of whether the transition came from a method-channel call
    // (manual pause/resume/end) or internally (timer auto-completion).
    var onSessionEnded: (() -> Unit)? = null
    var onSessionPaused: (() -> Unit)? = null
    var onSessionResumed: (() -> Unit)? = null

    init {
        restoreSessionFromPreferences()
    }

    // ==========================================
    // SESSION LIFECYCLE
    // ==========================================

    /**
     * Start a new focus session
     */
    fun startSession(sessionData: Map<String, Any>): Boolean {
        return try {
            Log.d(TAG, "📱 Starting focus session")

            // Parse session
            val session = FocusSession.fromMap(sessionData)

            // Validate
            if (session.sessionId.isEmpty() || session.userId.isEmpty()) {
                Log.e(TAG, "❌ Invalid session data")
                return false
            }

            // Store session
            currentSession = session
            sessionStartTime = System.currentTimeMillis()
            pausedElapsedTime = 0
            isPaused = false
            isActive = true

            // Persist to storage
            saveSessionToPreferences()

            // Start timer
            startTimer(session)

            // Notify Flutter
            sendEvent("session_started", mapOf(
                "sessionId" to session.sessionId,
                "sessionType" to session.sessionType,
                "plannedDuration" to session.plannedDuration,
                "startTime" to sessionStartTime
            ))

            Log.d(TAG, "✅ Session started: ${session.sessionId}")
            true

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting session", e)
            false
        }
    }

    /**
     * Pause current session
     */
    fun pauseSession(): Boolean {
        return try {
            if (!isActive || isPaused) {
                Log.w(TAG, "⚠️ Cannot pause: not active or already paused")
                return false
            }

            Log.d(TAG, "⏸️ Pausing session")

            // Calculate elapsed time
            pausedElapsedTime = System.currentTimeMillis() - sessionStartTime
            isPaused = true

            // Stop timer
            stopTimer()

            // Save state
            saveSessionToPreferences()

            // Notify Flutter
            sendEvent("session_paused", mapOf(
                "timestamp" to System.currentTimeMillis(),
                "elapsedTime" to pausedElapsedTime
            ))

            onSessionPaused?.invoke()

            Log.d(TAG, "✅ Session paused")
            true

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error pausing session", e)
            false
        }
    }

    /**
     * Resume paused session
     */
    fun resumeSession(): Boolean {
        return try {
            if (!isActive || !isPaused) {
                Log.w(TAG, "⚠️ Cannot resume: not active or not paused")
                return false
            }

            Log.d(TAG, "▶️ Resuming session")

            // Adjust start time
            sessionStartTime = System.currentTimeMillis() - pausedElapsedTime
            isPaused = false

            // Restart timer
            currentSession?.let { startTimer(it) }

            // Save state
            saveSessionToPreferences()

            // Notify Flutter
            sendEvent("session_resumed", mapOf(
                "timestamp" to System.currentTimeMillis(),
                "elapsedTime" to pausedElapsedTime
            ))

            onSessionResumed?.invoke()

            Log.d(TAG, "✅ Session resumed")
            true

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error resuming session", e)
            false
        }
    }

    /**
     * End current session
     */
    fun endSession(): Boolean {
        return try {
            if (!isActive) {
                Log.w(TAG, "⚠️ No active session to end")
                return false
            }

            Log.d(TAG, "🛑 Ending session")

            val session = currentSession
            if (session != null) {
                // Calculate final stats
                val endTime = System.currentTimeMillis()
                val totalElapsed = if (isPaused) pausedElapsedTime else endTime - sessionStartTime
                val actualDuration = (totalElapsed / 60000).toInt()
                val completionRate = if (session.plannedDuration > 0) {
                    (actualDuration.toFloat() / session.plannedDuration) * 100
                } else 100f

                // Notify Flutter with final data
                sendEvent("session_completed", mapOf(
                    "sessionId" to session.sessionId,
                    "actualDuration" to actualDuration,
                    "completionRate" to completionRate.coerceAtMost(100f),
                    "totalElapsed" to totalElapsed,
                    "interruptions" to session.interruptions.size,
                    "status" to if (completionRate >= 100f) "completed" else "ended_early"
                ))
            }

            // Stop timer
            stopTimer()

            // Clear state
            clearSessionFromPreferences()
            currentSession = null
            isActive = false
            isPaused = false
            sessionStartTime = 0
            pausedElapsedTime = 0

            onSessionEnded?.invoke()

            Log.d(TAG, "✅ Session ended")
            true

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error ending session", e)
            false
        }
    }

    // ==========================================
    // TIMER MANAGEMENT
    // ==========================================

    private fun startTimer(session: FocusSession) {
        stopTimer() // Clear any existing timer

        timerRunnable = object : Runnable {
            override fun run() {
                if (!isPaused && isActive) {
                    val elapsed = System.currentTimeMillis() - sessionStartTime

                    when (session.sessionType.lowercase()) {
                        "timer" -> {
                            val remaining = (session.plannedDuration * 60000L) - elapsed
                            sendTimerUpdate(elapsed, remaining)

                            if (remaining <= 0) {
                                // Timer finished
                                Log.d(TAG, "⏰ Timer completed")
                                endSession()
                                return
                            }
                        }
                        "stopwatch" -> {
                            sendTimerUpdate(elapsed, 0L)
                        }
                        "pomodoro" -> {
                            // TODO: Implement pomodoro logic if needed
                            sendTimerUpdate(elapsed, 0L)
                        }
                    }

                    // Schedule next tick
                    handler.postDelayed(this, 1000)
                }
            }
        }

        handler.post(timerRunnable!!)
    }

    private fun stopTimer() {
        timerRunnable?.let {
            handler.removeCallbacks(it)
            timerRunnable = null
        }
    }

    private fun sendTimerUpdate(elapsed: Long, remaining: Long) {
        sendEvent("timer_update", mapOf(
            "elapsed" to elapsed,
            "elapsedMinutes" to (elapsed / 60000).toInt(),
            "remaining" to remaining,
            "remainingMinutes" to (remaining / 60000).toInt()
        ))
    }

    // ==========================================
    // INTERRUPTION TRACKING
    // ==========================================

    /**
     * Record an interruption (called by monitoring service)
     */
    fun recordInterruption(
        packageName: String,
        appName: String,
        type: String,
        wasBlocked: Boolean
    ) {
        try {
            val interruption = Interruption(
                timestamp = System.currentTimeMillis(),
                type = type,
                appPackage = packageName,
                appName = appName,
                wasBlocked = wasBlocked
            )

            currentSession?.interruptions?.add(interruption)
            saveSessionToPreferences()

            sendEvent("interruption_recorded", mapOf(
                "packageName" to packageName,
                "appName" to appName,
                "type" to type,
                "wasBlocked" to wasBlocked,
                "totalInterruptions" to (currentSession?.interruptions?.size ?: 0)
            ))

            Log.d(TAG, "📝 Interruption recorded: $appName ($type)")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error recording interruption", e)
        }
    }

    // ==========================================
    // STATE QUERIES
    // ==========================================

    fun isSessionActive(): Boolean = isActive

    fun isSessionPaused(): Boolean = isPaused

    fun getCurrentSession(): FocusSession? = currentSession

    fun getSessionStartTime(): Long = sessionStartTime

    fun getCurrentSessionStatus(): Map<String, Any>? {
        val session = currentSession ?: return null

        val elapsed = if (isPaused) {
            pausedElapsedTime
        } else if (isActive) {
            System.currentTimeMillis() - sessionStartTime
        } else {
            0L
        }

        return mapOf(
            "sessionId" to session.sessionId,
            "isActive" to isActive,
            "isPaused" to isPaused,
            "elapsedTime" to elapsed,
            "elapsedMinutes" to (elapsed / 60000).toInt(),
            "plannedDuration" to session.plannedDuration,
            "sessionType" to session.sessionType,
            "blockedApps" to session.blockedApps,
            "completionRate" to if (session.plannedDuration > 0) {
                ((elapsed / 60000).toInt().toFloat() / session.plannedDuration) * 100
            } else 0f
        )
    }

    // ==========================================
    // PERSISTENCE
    // ==========================================

    private fun saveSessionToPreferences() {
        try {
            prefs.edit().apply {
                currentSession?.let {
                    putString(KEY_CURRENT_SESSION, JSONObject(it.toMap()).toString())
                }
                putLong(KEY_SESSION_START_TIME, sessionStartTime)
                putLong(KEY_PAUSED_TIME, pausedElapsedTime)
                putBoolean(KEY_IS_PAUSED, isPaused)
                putBoolean(KEY_IS_ACTIVE, isActive)
                apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving session", e)
        }
    }

    private fun clearSessionFromPreferences() {
        try {
            prefs.edit().apply {
                remove(KEY_CURRENT_SESSION)
                remove(KEY_SESSION_START_TIME)
                remove(KEY_PAUSED_TIME)
                putBoolean(KEY_IS_PAUSED, false)
                putBoolean(KEY_IS_ACTIVE, false)
                apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error clearing session", e)
        }
    }

    private fun restoreSessionFromPreferences() {
        try {
            if (prefs.getBoolean(KEY_IS_ACTIVE, false)) {
                val sessionJson = prefs.getString(KEY_CURRENT_SESSION, null)
                if (sessionJson != null) {
                    val sessionData = JSONObject(sessionJson).toMap()
                    currentSession = FocusSession.fromMap(sessionData)
                    sessionStartTime = prefs.getLong(KEY_SESSION_START_TIME, System.currentTimeMillis())
                    pausedElapsedTime = prefs.getLong(KEY_PAUSED_TIME, 0)
                    isPaused = prefs.getBoolean(KEY_IS_PAUSED, false)
                    isActive = true

                    if (!isPaused && currentSession != null) {
                        startTimer(currentSession!!)
                    }

                    Log.d(TAG, "✅ Session restored: ${currentSession?.sessionId}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error restoring session", e)
            clearSessionFromPreferences()
        }
    }

    // ==========================================
    // FLUTTER COMMUNICATION
    // ==========================================

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        // Send queued events
        if (sink != null) {
            eventQueue.forEach { (event, data) ->
                sendEvent(event, data)
            }
            eventQueue.clear()
        }
    }

    private fun sendEvent(event: String, data: Any) {
        try {
            val eventData = mapOf(
                "event" to event,
                "data" to data,
                "timestamp" to System.currentTimeMillis()
            )

            if (eventSink != null) {
                handler.post { eventSink?.success(eventData) }
            } else {
                eventQueue[event] = data
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error sending event: $event", e)
        }
    }

    fun cleanup() {
        stopTimer()
        eventSink = null
        eventQueue.clear()
    }
}

// Helper extension
private fun JSONObject.toMap(): Map<String, Any> {
    val map = mutableMapOf<String, Any>()
    keys().forEach { key -> map[key] = get(key) }
    return map
}