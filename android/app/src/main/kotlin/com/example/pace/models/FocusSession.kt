package com.example.pace.models


/**
 * FocusSession - Core data class representing a focus session
 */
data class FocusSession(
    val sessionId: String,
    val userId: String,
    val startTime: Long,
    var endTime: Long?  = null,
    val plannedDuration: Int, // minutes
    var actualDuration: Int = 0, // minutes
    val sessionType: String, // "timer", "stopwatch", "pomodoro"
    val timerMode: String = "focus", // "focus", "short_break", "long_break"
    val pomodoroData: PomodoroData? = null,
    val blockedApps: List<String> = emptyList(),
    val blockedWebsites:  List<Map<String, Any>> = emptyList(),
    val shortFormBlocked: Boolean = false,
    val shortFormBlocks: Map<String, Any> = emptyMap(),
    val notificationsBlocked:  Boolean = false,
    val notificationBlocks: Map<String, Any> = emptyMap(),
    val interruptions: MutableList<Interruption> = mutableListOf(),
    var status: String = "active", // "active", "paused", "completed", "ended_early"
    var completionRate: Float = 0f,
    val notes: String? = null,
    val tags: List<String> = emptyList(),
    val groupId: String? = null,
    val isGroupSession: Boolean = false
) {
    companion object {
        fun fromMap(map: Map<String, Any>): FocusSession {
            return FocusSession(
                sessionId = map["sessionId"] as?  String ?: "",
                userId = map["userId"] as? String ?:  "",
                startTime = (map["startTime"] as? Number)?.toLong() ?: System.currentTimeMillis(),
                endTime = (map["endTime"] as? Number)?.toLong(),
                plannedDuration = (map["plannedDuration"] as?  Number)?.toInt() ?: 25,
                actualDuration = (map["actualDuration"] as? Number)?.toInt() ?: 0,
                sessionType = map["sessionType"] as? String ?: "timer",
                timerMode = map["timerMode"] as? String ?: "focus",
                pomodoroData = (map["pomodoroData"] as? Map<String, Any>)?.let { PomodoroData.fromMap(it) },
                blockedApps = (map["blockedApps"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
                blockedWebsites = (map["blockedWebsites"] as? List<*>)?.filterIsInstance<Map<String, Any>>() ?: emptyList(),
                shortFormBlocked = map["shortFormBlocked"] as? Boolean ?: false,
                shortFormBlocks = (map["shortFormBlocks"] as? Map<String, Any>) ?: emptyMap(),
                notificationsBlocked = map["notificationsBlocked"] as? Boolean ?: false,
                notificationBlocks = (map["notificationBlocks"] as? Map<String, Any>) ?: emptyMap(),
                interruptions = ((map["interruptions"] as? List<*>)?.filterIsInstance<Map<String, Any>>()?.map {
                    Interruption.fromMap(it)
                } ?: emptyList()).toMutableList(),
                status = map["status"] as? String ?: "active",
                completionRate = (map["completionRate"] as? Number)?.toFloat() ?: 0f,
                notes = map["notes"] as? String,
                tags = (map["tags"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
                groupId = map["groupId"] as?  String,
                isGroupSession = map["isGroupSession"] as? Boolean ?: false
            )
        }
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "sessionId" to sessionId,
            "userId" to userId,
            "startTime" to startTime,
            "endTime" to endTime,
            "plannedDuration" to plannedDuration,
            "actualDuration" to actualDuration,
            "sessionType" to sessionType,
            "timerMode" to timerMode,
            "pomodoroData" to pomodoroData?.toMap(),
            "blockedApps" to blockedApps,
            "blockedWebsites" to blockedWebsites,
            "shortFormBlocked" to shortFormBlocked,
            "shortFormBlocks" to shortFormBlocks,
            "notificationsBlocked" to notificationsBlocked,
            "notificationBlocks" to notificationBlocks,
            "interruptions" to interruptions.map { it.toMap() },
            "status" to status,
            "completionRate" to completionRate,
            "notes" to notes,
            "tags" to tags,
            "groupId" to groupId,
            "isGroupSession" to isGroupSession
        ).filterValues { it != null } as Map<String, Any>
    }
}

/**
 * PomodoroData - Pomodoro session specific data
 */
data class PomodoroData(
    val currentCycle: Int = 1,
    val totalCycles: Int = 4,
    val isBreak: Boolean = false,
    val workDuration: Int = 25, // minutes
    val shortBreakDuration:  Int = 5, // minutes
    val longBreakDuration: Int = 15 // minutes
) {
    companion object {
        fun fromMap(map: Map<String, Any>): PomodoroData {
            return PomodoroData(
                currentCycle = (map["currentCycle"] as? Number)?.toInt() ?: 1,
                totalCycles = (map["totalCycles"] as? Number)?.toInt() ?: 4,
                isBreak = map["isBreak"] as? Boolean ?: false,
                workDuration = (map["workDuration"] as? Number)?.toInt() ?: 25,
                shortBreakDuration = (map["shortBreakDuration"] as? Number)?.toInt() ?: 5,
                longBreakDuration = (map["longBreakDuration"] as? Number)?.toInt() ?: 15
            )
        }
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "currentCycle" to currentCycle,
            "totalCycles" to totalCycles,
            "isBreak" to isBreak,
            "workDuration" to workDuration,
            "shortBreakDuration" to shortBreakDuration,
            "longBreakDuration" to longBreakDuration
        )
    }
}

/**
 * Interruption - Represents an interruption during focus session
 */
data class Interruption(
    val timestamp: Long,
    val type: String, // "app_opened", "notification_clicked", "manual_pause", "shorts_accessed", "website_accessed"
    val appPackage: String?  = null,
    val appName: String? = null,
    val wasBlocked: Boolean = false,
    val additional: Map<String, Any> = emptyMap()
) {
    companion object {
        fun fromMap(map: Map<String, Any>): Interruption {
            return Interruption(
                timestamp = (map["timestamp"] as? Number)?.toLong() ?: System.currentTimeMillis(),
                type = map["type"] as? String ?: "unknown",
                appPackage = map["appPackage"] as? String,
                appName = map["appName"] as? String,
                wasBlocked = map["wasBlocked"] as? Boolean ?: false,
                additional = (map["additional"] as? Map<String, Any>) ?: emptyMap()
            )
        }
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "timestamp" to timestamp,
            "type" to type,
            "appPackage" to appPackage,
            "appName" to appName,
            "wasBlocked" to wasBlocked,
            "additional" to additional
        ).filterValues { it != null } as Map<String, Any>
    }
}