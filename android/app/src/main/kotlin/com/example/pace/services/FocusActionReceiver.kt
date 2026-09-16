package com.example.pace.services


import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.lockin.focus.FocusModeManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * FocusActionReceiver - Handles actions from notification buttons
 */
class FocusActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "FocusActionReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d(TAG, "Received action:  $action")

        val focusManager = FocusModeManager.getInstance(context)
        val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

        when (action) {
            "PAUSE_SESSION" -> {
                scope.launch {
                    try {
                        val success = focusManager.pauseSession()
                        Log.d(TAG, "Pause session result: $success")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error pausing session", e)
                    }
                }
            }

            "END_SESSION" -> {
                scope.launch {
                    try {
                        val success = focusManager.endSession()
                        Log. d(TAG, "End session result: $success")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error ending session", e)
                    }
                }
            }

            else -> {
                Log.w(TAG, "Unknown action: $action")
            }
        }
    }
}