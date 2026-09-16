package com.example.pace.services

import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.example.pace.services.limits.AppLimitManager
import com.lockin.focus.FocusModeManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * UsageTrackingJobService - Background job for app limit monitoring
 * Ensures app limits are checked even when main service is not running
 */
class UsageTrackingJobService : JobService() {

    companion object {
        private const val TAG = "UsageTrackingJob"
    }

    private var jobScope:  CoroutineScope? = null

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onStartJob(params: JobParameters): Boolean {
        Log.d(TAG, "Usage tracking job started")

        jobScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

        jobScope?.launch {
            try {
                // Don't create a new AppLimitManager instance if no app limits are set
                // This prevents unnecessary job scheduling spam
                val focusManager = FocusModeManager.getInstance(this@UsageTrackingJobService)

                // Only proceed if there are actual app limits configured
                val sharedPrefs = getSharedPreferences("app_limits", MODE_PRIVATE)
                val hasAppLimits = sharedPrefs.all.isNotEmpty()

                if (!hasAppLimits && !focusManager.isSessionActive()) {
                    Log.d(TAG, "No app limits configured and no active session - skipping job")
                    return@launch
                }

                val appLimitManager = AppLimitManager(this@UsageTrackingJobService)

                // Check all app limits
                val limitStatuses = appLimitManager.checkAllAppLimits()
                Log.d(TAG, "Checked limits for ${limitStatuses.size} apps")

                // Ensure monitoring service is running if session is active
                if (focusManager.isSessionActive()) {
                    ensureMonitoringServiceRunning()
                }

            } catch (e:  Exception) {
                Log.e(TAG, "Error in usage tracking job", e)
            } finally {
                // Job completed
                jobFinished(params, false)
            }
        }

        return true // Job is running asynchronously
    }

    override fun onStopJob(params: JobParameters): Boolean {
        Log.d(TAG, "Usage tracking job stopped")
        jobScope?.cancel()
        return false // Don't reschedule
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun ensureMonitoringServiceRunning() {
        try {
            if (!isServiceRunning(AppMonitoringService:: class.java)) {
                Log.d(TAG, "Monitoring service not running, restarting...")
                val intent = Intent(this, AppMonitoringService::class.java).apply {
                    action = AppMonitoringService. ACTION_START_MONITORING
                }
                startForegroundService(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error ensuring monitoring service is running", e)
        }
    }

    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        val manager = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
        for (service in manager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClass.name == service.service. className) {
                return true
            }
        }
        return false
    }
}