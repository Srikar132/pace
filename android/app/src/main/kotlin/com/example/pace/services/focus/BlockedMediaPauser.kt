package com.example.pace.services.focus

import android.content.ComponentName
import android.content.Context
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.util.Log
import com.example.pace.services.notifications.NotificationBlockingService

/** Which playback states should be paused. Pure (constants are inlined) so it is unit tested. */
object MediaPausePolicy {
    fun shouldPause(playbackState: Int?): Boolean =
        playbackState == PlaybackState.STATE_PLAYING || playbackState == PlaybackState.STATE_BUFFERING
}

/**
 * Pauses the media session of a blocked app that is covered by a focus cover, so audio/video stops
 * behind the cover. Only the blocked app's own session is touched.
 *
 * Android gives no way to freeze an arbitrary app; this works for apps that publish a media session
 * (YouTube, Spotify...). It needs Pace's notification access (the listener component is what authorises
 * MediaSessionManager.getActiveSessions), so without that grant it logs once and does nothing.
 */
class BlockedMediaPauser(private val context: Context) {

    private companion object {
        const val TAG = "BlockedMediaPauser"
        const val MIN_INTERVAL_MS = 700L
    }

    private val manager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val listener = ComponentName(context, NotificationBlockingService::class.java)
    private var lastRun = 0L
    private var warnedNoAccess = false

    fun pause(packages: Set<String>) {
        if (packages.isEmpty()) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastRun < MIN_INTERVAL_MS) return
        lastRun = now
        try {
            manager.getActiveSessions(listener)
                .filter { it.packageName in packages && MediaPausePolicy.shouldPause(it.playbackState?.state) }
                .forEach {
                    Log.d(TAG, "Pausing ${it.packageName}")
                    it.transportControls.pause()
                }
        } catch (e: SecurityException) {
            if (!warnedNoAccess) {
                warnedNoAccess = true
                Log.w(TAG, "Notification access not granted: cannot pause blocked media")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error pausing media", e)
        }
    }
}
