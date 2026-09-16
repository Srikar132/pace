package com.example.pace.services


import android.os.Handler
import android.os.Looper
import android.util. Log
import com.example.pace.models.FocusSession
import com.example.pace.models.PomodoroData

/**
 * PomodoroManager - Handles Pomodoro technique timing and cycles
 */
class PomodoroManager(
    private val session: FocusSession,
    private val onTick: (phase: String, elapsed: Long, remaining: Long) -> Unit
) {
    companion object {
        private const val TAG = "PomodoroManager"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var timerRunnable: Runnable? = null
    private var isRunning = false

    private var currentPhase = "work" // "work", "short_break", "long_break"
    private var currentCycle = 1
    private var phaseStartTime = 0L

    private val pomodoroData = session.pomodoroData ?: PomodoroData()

    fun start() {
        if (isRunning) {
            Log.w(TAG, "Pomodoro timer already running")
            return
        }

        Log.d(TAG, "Starting Pomodoro timer")
        isRunning = true
        phaseStartTime = System.currentTimeMillis()
        currentPhase = "work"
        currentCycle = 1

        startTimer()
    }

    fun stop() {
        Log.d(TAG, "Stopping Pomodoro timer")
        isRunning = false
        timerRunnable?.let { handler.removeCallbacks(it) }
        timerRunnable = null
    }

    fun startWork() {
        if (!isRunning) return

        Log.d(TAG, "Starting work phase, cycle: $currentCycle")
        currentPhase = "work"
        phaseStartTime = System.currentTimeMillis()
        startTimer()
    }

    fun startBreak() {
        if (!isRunning) return

        val isLongBreak = currentCycle % pomodoroData.totalCycles == 0
        currentPhase = if (isLongBreak) "long_break" else "short_break"

        Log.d(TAG, "Starting ${currentPhase} phase after cycle: $currentCycle")
        phaseStartTime = System.currentTimeMillis()

        if (isLongBreak) {
            currentCycle = 1 // Reset cycle counter after long break
        } else {
            currentCycle++
        }

        startTimer()
    }

    private fun startTimer() {
        timerRunnable?.let { handler.removeCallbacks(it) }

        timerRunnable = object : Runnable {
            override fun run() {
                if (!isRunning) return

                val elapsed = System.currentTimeMillis() - phaseStartTime
                val phaseDuration = getPhaseDuration() * 60000L // Convert to milliseconds
                val remaining = phaseDuration - elapsed

                onTick(currentPhase, elapsed, remaining)

                if (remaining <= 0) {
                    // Phase completed
                    when (currentPhase) {
                        "work" -> {
                            Log.d(TAG, "Work phase completed, starting break")
                            startBreak()
                        }
                        "short_break", "long_break" -> {
                            Log.d(TAG, "Break phase completed, starting work")
                            startWork()
                        }
                    }
                } else {
                    // Schedule next tick
                    handler. postDelayed(this, 1000)
                }
            }
        }

        handler.post(timerRunnable!!)
    }

    private fun getPhaseDuration(): Int {
        return when (currentPhase) {
            "work" -> pomodoroData.workDuration
            "short_break" -> pomodoroData.shortBreakDuration
            "long_break" -> pomodoroData.longBreakDuration
            else -> pomodoroData.workDuration
        }
    }

    fun getCurrentPhase(): String = currentPhase
    fun getCurrentCycle(): Int = currentCycle
    fun isRunning(): Boolean = isRunning
}