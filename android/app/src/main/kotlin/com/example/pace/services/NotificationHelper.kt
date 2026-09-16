package com.example.pace.services

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.pace.MainActivity

/**
 * NotificationHelper - Complete notification management for all app features
 */
object NotificationHelper {

    private const val TAG = "NotificationHelper"

    // Notification channels
    private const val FOCUS_CHANNEL_ID = "focus_monitoring"
    private const val LIMITS_CHANNEL_ID = "app_limits"
    private const val BLOCKS_CHANNEL_ID = "app_blocks"
    private const val EDUCATIONAL_CHANNEL_ID = "educational_notifications"
    private const val ACHIEVEMENTS_CHANNEL_ID = "achievements"

    fun createAllNotificationChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(NotificationManager::class. java)

            // Focus Monitoring Channel
            val focusChannel = NotificationChannel(
                FOCUS_CHANNEL_ID,
                "Focus Mode",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing focus session notifications"
                setShowBadge(false)
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
            }

            // App Limits Channel
            val limitsChannel = NotificationChannel(
                LIMITS_CHANNEL_ID,
                "App Limits",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications about app usage limits"
                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
            }

            // App Blocks Channel
            val blocksChannel = NotificationChannel(
                BLOCKS_CHANNEL_ID,
                "Content Blocks",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications when content is blocked"
                enableLights(false)
                enableVibration(false)
                setShowBadge(true)
            }

            // Educational Channel
            val educationalChannel = NotificationChannel(
                EDUCATIONAL_CHANNEL_ID,
                "Educational Tips",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Educational content about digital wellness"
                enableLights(true)
                lightColor = android.graphics. Color.BLUE
                enableVibration(false)
                setShowBadge(true)
            }

            // Achievements Channel
            val achievementsChannel = NotificationChannel(
                ACHIEVEMENTS_CHANNEL_ID,
                "Achievements",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Focus achievements and milestones"
                enableLights(true)
                lightColor = android.graphics. Color.GREEN
                enableVibration(true)
                setShowBadge(true)
            }

            notificationManager.createNotificationChannels(listOf(
                focusChannel,
                limitsChannel,
                blocksChannel,
                educationalChannel,
                achievementsChannel
            ))
        }
    }

    // ====================
    // APP LIMITS NOTIFICATIONS
    // ====================

    fun showLimitWarning(
        context: Context,
        appName: String,
        percentage: String,
        limitMinutes: Int,
        usedMinutes: Int
    ) {
        try {
            createAllNotificationChannels(context)
            val notificationManager = context.getSystemService(NotificationManager::class.java)

            val notification = NotificationCompat.Builder(context, LIMITS_CHANNEL_ID)
                .setContentTitle("$percentage of daily limit reached")
                .setContentText("$appName:  ${usedMinutes}/${limitMinutes} minutes used today")
                .setSmallIcon(android.R.drawable.ic_dialog_alert) // Using system icon
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setCategory(NotificationCompat. CATEGORY_REMINDER)
                .setColor(android.graphics. Color. YELLOW)
                .build()

            notificationManager.notify(
                "limit_warning_${appName}_$percentage".hashCode(),
                notification
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing limit warning notification", e)
        }
    }

    fun showLimitExceeded(
        context: Context,
        appName: String,
        limitMinutes: Int,
        usedMinutes: Int,
        timeUntilReset: Long
    ) {
        try {
            createAllNotificationChannels(context)
            val notificationManager = context.getSystemService(NotificationManager::class.java)
            val hoursUntilReset = (timeUntilReset / (1000 * 60 * 60)).toInt()

            val notification = NotificationCompat.Builder(context, LIMITS_CHANNEL_ID)
                .setContentTitle("Daily limit exceeded")
                .setContentText("$appName: ${usedMinutes}/${limitMinutes} minutes. Resets in ${hoursUntilReset}h")
                .setSmallIcon(android.R.drawable.ic_dialog_alert) // Using system icon
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setCategory(NotificationCompat. CATEGORY_REMINDER)
                .setColor(android.graphics.Color.RED)
                .build()

            notificationManager.notify(
                "limit_exceeded_$appName". hashCode(),
                notification
            )
        } catch (e:  Exception) {
            Log.e(TAG, "Error showing limit exceeded notification", e)
        }
    }

    // ====================
    // EDUCATIONAL NOTIFICATIONS
    // ====================

    fun showEducationalNotification(
        context:  Context,
        title: String,
        message: String,
        contentType: String
    ) {
        try {
            createAllNotificationChannels(context)
            val notificationManager = context. getSystemService(NotificationManager:: class.java)

            // Create intent for learning more
            val learnMoreIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("show_education", contentType)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            val learnMorePendingIntent = PendingIntent.getActivity(
                context,
                contentType.hashCode(),
                learnMoreIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(context, EDUCATIONAL_CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setSmallIcon(android.R.drawable.ic_dialog_info) // Using system icon
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .addAction(
                    android.R.drawable.ic_menu_info_details, // Using system icon
                    "Learn More",
                    learnMorePendingIntent
                )
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setColor(android.graphics.Color.BLUE)
                .build()

            notificationManager.notify(
                "educational_${contentType}_${System.currentTimeMillis()}".hashCode(),
                notification
            )

        } catch (e: Exception) {
            Log.e(TAG, "Error showing educational notification", e)
        }
    }

    // ====================
    // ACHIEVEMENT NOTIFICATIONS
    // ====================

    fun showFocusAchievement(
        context:  Context,
        title: String,
        message: String,
        focusTimeMinutes: Int
    ) {
        try {
            createAllNotificationChannels(context)
            val notificationManager = context.getSystemService(NotificationManager::class.java)

            val notification = NotificationCompat.Builder(context, ACHIEVEMENTS_CHANNEL_ID)
                .setContentTitle("🎯 $title")
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setSmallIcon(android.R.drawable.star_big_on) // Using system icon
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setColor(android.graphics.Color.GREEN)
                .setVibrate(longArrayOf(0, 200, 100, 200))
                .build()

            notificationManager.notify(
                "achievement_${System.currentTimeMillis()}".hashCode(),
                notification
            )

        } catch (e: Exception) {
            Log.e(TAG, "Error showing achievement notification", e)
        }
    }

    fun showSessionCompleted(
        context: Context,
        focusTimeMinutes:  Int,
        blockedInterruptions: Int,
        completionRate: Float
    ) {
        try {
            val title = when {
                completionRate >= 100f -> "Perfect Focus Session! 🌟"
                completionRate >= 75f -> "Great Focus Session! 👏"
                completionRate >= 50f -> "Good Focus Session!  👍"
                else -> "Focus Session Completed"
            }

            val message = "Focused for ${focusTimeMinutes} minutes, blocked ${blockedInterruptions} distractions. " +
                    "${completionRate.toInt()}% completion rate!"

            showFocusAchievement(context, title, message, focusTimeMinutes)

        } catch (e: Exception) {
            Log.e(TAG, "Error showing session completed notification", e)
        }
    }

    // ====================
    // BLOCK NOTIFICATIONS
    // ====================

    fun showContentBlocked(
        context: Context,
        contentType: String,
        appName: String
    ) {
        try {
            createAllNotificationChannels(context)
            val notificationManager = context. getSystemService(NotificationManager:: class.java)

            val message = when (contentType.lowercase()) {
                "app" -> "$appName was blocked during focus session"
                "shorts", "reels" -> "$contentType blocked - stay focused!"
                "website" -> "Website blocked:  $appName"
                else -> "Content blocked during focus session"
            }

            val notification = NotificationCompat.Builder(context, BLOCKS_CHANNEL_ID)
                .setContentTitle("Content Blocked")
                .setContentText(message)
                .setSmallIcon(android.R. drawable.ic_delete) // Using system icon
                . setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setTimeoutAfter(5000) // Auto dismiss after 5 seconds
                .build()

            notificationManager.notify(
                "block_${contentType}_${System.currentTimeMillis()}".hashCode(),
                notification
            )

        } catch (e: Exception) {
            Log.e(TAG, "Error showing content blocked notification", e)
        }
    }
}