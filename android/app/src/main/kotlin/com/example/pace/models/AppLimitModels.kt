package com.example.pace.models


/**
 * AppLimit - Configuration for app usage limits
 */
data class AppLimit(
    val dailyLimitMinutes: Int,
    val weeklyLimitMinutes: Int? = null,
    val actionOnExceed:  String = "block", // "block", "warn", "notify"
    val isActive: Boolean = true
) {
    companion object {
        fun fromMap(map: Map<String, Any>): AppLimit {
            return AppLimit(
                dailyLimitMinutes = (map["dailyLimit"] as?  Number)?.toInt() ?: 0,
                weeklyLimitMinutes = (map["weeklyLimit"] as? Number)?.toInt(),
                actionOnExceed = map["actionOnExceed"] as? String ?:  "block",
                isActive = map["isActive"] as? Boolean ?: true
            )
        }
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "dailyLimit" to dailyLimitMinutes,
            "weeklyLimit" to weeklyLimitMinutes,
            "actionOnExceed" to actionOnExceed,
            "isActive" to isActive
        ).filterValues { it != null } as Map<String, Any>
    }
}

/**
 * AppLimitStatus - Current status of an app's usage vs limits
 */
data class AppLimitStatus(
    val packageName: String,
    val appName:  String,
    val usedMinutes: Int,
    val limitMinutes: Int,
    val percentageUsed: Int,
    val status: LimitStatusType,
    val actionOnExceed: String,
    val timeUntilReset: Long
)

/**
 * LimitStatusType - Enum for different limit status types
 */
enum class LimitStatusType {
    OK,
    WARNING_75,
    WARNING_90,
    EXCEEDED,
    ERROR
}

/**
 * AppUsageStats - Usage statistics for an app
 */
data class AppUsageStats(
    val packageName: String,
    val appName: String,
    val todayUsageMs:  Long,
    val todayUsageMinutes: Int,
    val weeklyUsageMs: Long,
    val weeklyUsageMinutes: Int,
    val lastUsed: Long
)