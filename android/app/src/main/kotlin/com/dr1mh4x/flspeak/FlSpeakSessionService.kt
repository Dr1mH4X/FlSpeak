package com.dr1mh4x.flspeak

import android.Manifest
import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * 语音连接期的统一常驻前台服务：维护单条常驻通知、按当前权限与共享态动态组合
 * foregroundServiceType，并通过回调把通知栏按钮动作回传给 Flutter。
 */
class FlSpeakSessionService : Service() {
    data class SessionNotificationPayload(
        val title: String,
        val subtitle: String,
        val channelName: String,
        val muteActionLabel: String,
        val stopScreenShareActionLabel: String,
        val disconnectActionLabel: String,
        val isMuted: Boolean,
        val isSharingScreen: Boolean,
        val includeMediaProjection: Boolean,
        val sessionEpoch: Int,
    )

    companion object {
        private const val TAG = "FlSpeakSessionService"
        private const val CHANNEL_ID = "flspeak_session_ongoing"
        private const val DEFAULT_CHANNEL_NAME = "Voice session"
        private const val NOTIFICATION_ID = 2001

        private const val ACTION_SYNC = "com.dr1mh4x.flspeak.action.SESSION_SYNC"
        private const val ACTION_TOGGLE_MUTE = "com.dr1mh4x.flspeak.action.SESSION_TOGGLE_MUTE"
        private const val ACTION_STOP_SCREEN_SHARE =
            "com.dr1mh4x.flspeak.action.SESSION_STOP_SCREEN_SHARE"
        private const val ACTION_DISCONNECT = "com.dr1mh4x.flspeak.action.SESSION_DISCONNECT"

        const val EVENT_TOGGLE_MUTE = "toggleMute"
        const val EVENT_STOP_SCREEN_SHARE = "stopScreenShare"
        const val EVENT_DISCONNECT = "disconnect"

        private const val REQUEST_CODE_OPEN_APP = 2100
        private const val REQUEST_CODE_TOGGLE_MUTE = 2101
        private const val REQUEST_CODE_STOP_SCREEN_SHARE = 2102
        private const val REQUEST_CODE_DISCONNECT = 2103

        private const val EXTRA_REQUEST_ID = "request_id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_SUBTITLE = "subtitle"
        private const val EXTRA_CHANNEL_NAME = "channel_name"
        private const val EXTRA_MUTE_ACTION_LABEL = "mute_action_label"
        private const val EXTRA_STOP_SCREEN_SHARE_LABEL = "stop_screen_share_label"
        private const val EXTRA_DISCONNECT_ACTION_LABEL = "disconnect_action_label"
        private const val EXTRA_IS_MUTED = "is_muted"
        private const val EXTRA_IS_SHARING_SCREEN = "is_sharing_screen"
        private const val EXTRA_INCLUDE_MEDIA_PROJECTION = "include_media_projection"
        private const val EXTRA_SESSION_EPOCH = "session_epoch"

        private val mainHandler = Handler(Looper.getMainLooper())
        private var activeInstance: FlSpeakSessionService? = null
        private var actionListener: ((String) -> Unit)? = null
        private var nextRequestId: Long = 1L
        private var minValidRequestId: Long = 0L
        private var pendingForegroundStart: Boolean = false
        private val pendingSyncCallbacks = LinkedHashMap<Long, (Boolean) -> Unit>()

        fun setActionListener(listener: ((String) -> Unit)?) {
            actionListener = listener
        }

        fun clearActionListener(expected: (String) -> Unit) {
            if (actionListener === expected) {
                actionListener = null
            }
        }

        fun sync(
            context: Context,
            payload: SessionNotificationPayload,
            onComplete: (Boolean) -> Unit,
        ) {
            val requestId = nextRequestId++
            pendingSyncCallbacks[requestId] = onComplete
            val intent =
                Intent(context, FlSpeakSessionService::class.java).apply {
                    action = ACTION_SYNC
                    putExtra(EXTRA_REQUEST_ID, requestId)
                    putExtra(EXTRA_TITLE, payload.title)
                    putExtra(EXTRA_SUBTITLE, payload.subtitle)
                    putExtra(EXTRA_CHANNEL_NAME, payload.channelName)
                    putExtra(EXTRA_MUTE_ACTION_LABEL, payload.muteActionLabel)
                    putExtra(EXTRA_STOP_SCREEN_SHARE_LABEL, payload.stopScreenShareActionLabel)
                    putExtra(EXTRA_DISCONNECT_ACTION_LABEL, payload.disconnectActionLabel)
                    putExtra(EXTRA_IS_MUTED, payload.isMuted)
                    putExtra(EXTRA_IS_SHARING_SCREEN, payload.isSharingScreen)
                    putExtra(EXTRA_INCLUDE_MEDIA_PROJECTION, payload.includeMediaProjection)
                    putExtra(EXTRA_SESSION_EPOCH, payload.sessionEpoch)
                }
            try {
                if (activeInstance?.isForegroundActive == true) {
                    try {
                        context.startService(intent)
                    } catch (_: IllegalStateException) {
                        pendingForegroundStart = true
                        ContextCompat.startForegroundService(context, intent)
                    }
                } else {
                    pendingForegroundStart = true
                    ContextCompat.startForegroundService(context, intent)
                }
            } catch (error: SecurityException) {
                pendingForegroundStart = false
                pendingSyncCallbacks.remove(requestId)
                Log.w(TAG, "Failed to start foreground service due to security policy", error)
                onComplete(false)
            } catch (error: IllegalStateException) {
                pendingForegroundStart = false
                pendingSyncCallbacks.remove(requestId)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && Api31Impl.isStartNotAllowed(error)) {
                    Log.w(TAG, "Foreground service start not allowed in current app state", error)
                } else {
                    Log.w(TAG, "Failed to start foreground service due to illegal state", error)
                }
                onComplete(false)
            }
        }

        fun stop(context: Context) {
            minValidRequestId = nextRequestId
            val staleIds = pendingSyncCallbacks.keys.filter { it < minValidRequestId }
            for (id in staleIds) {
                pendingSyncCallbacks.remove(id)?.invoke(false)
            }
            val instance = activeInstance
            if (instance != null) {
                instance.stopForegroundAndSelf()
                return
            }
            // 若 startForegroundService 仍在派发途中，等待 onStartCommand 补齐 startForeground 后再退出，
            // 避免系统抛出 ForegroundServiceDidNotStartInTimeException。
            if (!pendingForegroundStart) {
                context.stopService(Intent(context, FlSpeakSessionService::class.java))
            }
        }

        private fun dispatchAction(action: String): Boolean {
            val listener = actionListener ?: return false
            if (Looper.myLooper() == Looper.getMainLooper()) {
                listener(action)
            } else {
                mainHandler.post { actionListener?.invoke(action) }
            }
            return true
        }
    }

    private var isForegroundActive = false
    private var activeSessionEpoch: Int? = null
    private var sessionStartedAtMs: Long = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            if (!isForegroundActive) {
                stopSelf()
            }
            return START_NOT_STICKY
        }

        when (intent.action) {
            ACTION_SYNC -> {
                val startedViaForegroundService = pendingForegroundStart
                pendingForegroundStart = false
                val requestId = intent.getLongExtra(EXTRA_REQUEST_ID, 0L)
                val payload = extractPayload(intent)
                if (requestId < minValidRequestId) {
                    if (!isForegroundActive) {
                        startForegroundSafely(payload, mediaPlaybackOnly = true)
                    }
                    pendingSyncCallbacks.remove(requestId)?.invoke(false)
                    if (pendingSyncCallbacks.keys.none { it >= minValidRequestId }) {
                        stopForegroundAndSelf(startId)
                    }
                    return START_NOT_STICKY
                }

                if (activeSessionEpoch != payload.sessionEpoch || sessionStartedAtMs == 0L) {
                    activeSessionEpoch = payload.sessionEpoch
                    sessionStartedAtMs = System.currentTimeMillis()
                }
                val ok = startForegroundSafely(payload, mediaPlaybackOnly = false)
                if (!ok && !isForegroundActive) {
                    if (startedViaForegroundService) {
                        startForegroundSafely(payload, mediaPlaybackOnly = true)
                        stopForegroundAndSelf(startId)
                    } else {
                        stopSelf(startId)
                    }
                }
                pendingSyncCallbacks.remove(requestId)?.invoke(ok)
            }
            ACTION_TOGGLE_MUTE -> dispatchAction(EVENT_TOGGLE_MUTE)
            ACTION_STOP_SCREEN_SHARE -> dispatchAction(EVENT_STOP_SCREEN_SHARE)
            ACTION_DISCONNECT -> {
                if (!dispatchAction(EVENT_DISCONNECT)) {
                    stopForegroundAndSelf()
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        dispatchAction(EVENT_DISCONNECT)
        stopForegroundAndSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (activeInstance === this) {
            activeInstance = null
        }
        isForegroundActive = false
        activeSessionEpoch = null
        sessionStartedAtMs = 0L
        pendingForegroundStart = false
        val remaining = pendingSyncCallbacks.values.toList()
        pendingSyncCallbacks.clear()
        for (callback in remaining) {
            callback(false)
        }
        super.onDestroy()
    }

    private fun extractPayload(intent: Intent): SessionNotificationPayload =
        SessionNotificationPayload(
            title = intent.getStringExtra(EXTRA_TITLE).orEmpty(),
            subtitle = intent.getStringExtra(EXTRA_SUBTITLE).orEmpty(),
            channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME).orEmpty(),
            muteActionLabel = intent.getStringExtra(EXTRA_MUTE_ACTION_LABEL).orEmpty(),
            stopScreenShareActionLabel =
                intent.getStringExtra(EXTRA_STOP_SCREEN_SHARE_LABEL).orEmpty(),
            disconnectActionLabel =
                intent.getStringExtra(EXTRA_DISCONNECT_ACTION_LABEL).orEmpty(),
            isMuted = intent.getBooleanExtra(EXTRA_IS_MUTED, false),
            isSharingScreen = intent.getBooleanExtra(EXTRA_IS_SHARING_SCREEN, false),
            includeMediaProjection =
                intent.getBooleanExtra(EXTRA_INCLUDE_MEDIA_PROJECTION, false),
            sessionEpoch = intent.getIntExtra(EXTRA_SESSION_EPOCH, 0),
        )

    private fun computeForegroundServiceTypes(
        includeMediaProjection: Boolean,
        mediaPlaybackOnly: Boolean,
    ): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return 0
        }
        var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        if (mediaPlaybackOnly) {
            return types
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                    PackageManager.PERMISSION_GRANTED
        ) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        if (includeMediaProjection) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        }
        return types
    }

    private fun startForegroundSafely(
        payload: SessionNotificationPayload,
        mediaPlaybackOnly: Boolean,
    ): Boolean {
        ensureNotificationChannel(payload.channelName)
        val notification = buildNotification(payload)
        val serviceTypes =
            computeForegroundServiceTypes(
                includeMediaProjection = payload.includeMediaProjection,
                mediaPlaybackOnly = mediaPlaybackOnly,
            )
        return try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, serviceTypes)
            isForegroundActive = true
            true
        } catch (error: SecurityException) {
            Log.w(TAG, "Foreground service start denied by security policy", error)
            false
        } catch (error: IllegalStateException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && Api31Impl.isStartNotAllowed(error)) {
                Log.w(TAG, "Foreground service start not allowed in current app state", error)
            } else {
                Log.w(TAG, "Foreground service start failed with illegal state", error)
            }
            false
        }
    }

    private fun ensureNotificationChannel(channelName: String) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val resolvedName = channelName.ifBlank { DEFAULT_CHANNEL_NAME }
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                resolvedName,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(payload: SessionNotificationPayload): Notification {
        val builder =
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_session)
                .setContentTitle(payload.title)
                .setContentText(payload.subtitle)
                .setContentIntent(contentPendingIntent())
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setWhen(
                    if (sessionStartedAtMs > 0L) {
                        sessionStartedAtMs
                    } else {
                        System.currentTimeMillis()
                    },
                )
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        if (payload.muteActionLabel.isNotBlank()) {
            builder.addAction(
                0,
                payload.muteActionLabel,
                actionPendingIntent(ACTION_TOGGLE_MUTE, REQUEST_CODE_TOGGLE_MUTE),
            )
        }
        if (payload.isSharingScreen && payload.stopScreenShareActionLabel.isNotBlank()) {
            builder.addAction(
                0,
                payload.stopScreenShareActionLabel,
                actionPendingIntent(ACTION_STOP_SCREEN_SHARE, REQUEST_CODE_STOP_SCREEN_SHARE),
            )
        }
        if (payload.disconnectActionLabel.isNotBlank()) {
            builder.addAction(
                0,
                payload.disconnectActionLabel,
                actionPendingIntent(ACTION_DISCONNECT, REQUEST_CODE_DISCONNECT),
            )
        }
        return builder.build()
    }

    private fun contentPendingIntent(): PendingIntent {
        val launchIntent =
            Intent(this, MainActivity::class.java).apply {
                flags =
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_NEW_TASK
            }
        return PendingIntent.getActivity(
            this,
            REQUEST_CODE_OPEN_APP,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun actionPendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, FlSpeakSessionService::class.java).apply { this.action = action }
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun stopForegroundAndSelf(startId: Int? = null) {
        isForegroundActive = false
        activeSessionEpoch = null
        sessionStartedAtMs = 0L
        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Failed to remove foreground notification cleanly", error)
        }
        if (startId != null) {
            stopSelf(startId)
        } else {
            stopSelf()
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private object Api31Impl {
        fun isStartNotAllowed(error: Throwable): Boolean =
            error is ForegroundServiceStartNotAllowedException
    }
}
