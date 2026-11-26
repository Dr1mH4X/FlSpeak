package com.dr1mh4x.flspeak

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val MIC_PERMISSION_REQUEST_CODE = 1001
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1002

        init {
            System.loadLibrary("flspeak_ffi")
        }
    }

    private var dnsCallback: ConnectivityManager.NetworkCallback? = null
    private var pendingMicPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private val pendingSessionSyncResults = mutableSetOf<MethodChannel.Result>()
    private var sessionActionSink: EventChannel.EventSink? = null
    private var sessionActionListener: ((String) -> Unit)? = null

    private external fun nativeInitAndroidContext(context: Context)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        nativeInitAndroidContext(applicationContext)
        super.configureFlutterEngine(flutterEngine)
        registerFilesChannel(flutterEngine)
        registerNetworkDnsChannels(flutterEngine)
        registerAudioPermissionChannel(flutterEngine)
        registerAppLifecycleChannel(flutterEngine)
        registerSessionServiceChannels(flutterEngine)
    }

    override fun onDestroy() {
        pendingMicPermissionResult?.success("denied")
        pendingMicPermissionResult = null
        pendingNotificationPermissionResult?.success(false)
        pendingNotificationPermissionResult = null
        val pendingSyncs = pendingSessionSyncResults.toList()
        pendingSessionSyncResults.clear()
        for (result in pendingSyncs) {
            result.success(false)
        }
        sessionActionSink = null
        sessionActionListener?.let { FlSpeakSessionService.clearActionListener(it) }
        sessionActionListener = null
        unregisterDnsCallback()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            MIC_PERMISSION_REQUEST_CODE -> {
                val result = pendingMicPermissionResult ?: return
                pendingMicPermissionResult = null
                val granted =
                    grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
                val status =
                    when {
                        granted -> "granted"
                        !shouldShowRequestPermissionRationale(
                            Manifest.permission.RECORD_AUDIO,
                        ) -> "permanentlyDenied"
                        else -> "denied"
                    }
                result.success(status)
            }
            NOTIFICATION_PERMISSION_REQUEST_CODE -> {
                val result = pendingNotificationPermissionResult ?: return
                pendingNotificationPermissionResult = null
                val granted =
                    grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
                result.success(granted)
            }
        }
    }

    private fun registerAudioPermissionChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flspeak/audio_permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMicrophonePermission" -> {
                        if (
                            checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                                PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success("granted")
                            return@setMethodCallHandler
                        }
                        if (pendingMicPermissionResult != null) {
                            result.error(
                                "permission_in_progress",
                                "Microphone permission request already in progress",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        pendingMicPermissionResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            MIC_PERMISSION_REQUEST_CODE,
                        )
                    }
                    "openAppSettings" -> {
                        val intent =
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null),
                            )
                        val launched =
                            try {
                                startActivity(intent)
                                true
                            } catch (_: Exception) {
                                false
                            }
                        result.success(launched)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerAppLifecycleChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flspeak/app_lifecycle")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBackground" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerSessionServiceChannels(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "flspeak/session_service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                                PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (pendingNotificationPermissionResult != null) {
                            result.error(
                                "permission_in_progress",
                                "Notification permission request already in progress",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        pendingNotificationPermissionResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            NOTIFICATION_PERMISSION_REQUEST_CODE,
                        )
                    }
                    "syncSession" -> {
                        val payload =
                            FlSpeakSessionService.SessionNotificationPayload(
                                title = call.argument<String>("title").orEmpty(),
                                subtitle = call.argument<String>("subtitle").orEmpty(),
                                channelName = call.argument<String>("channelName").orEmpty(),
                                muteActionLabel =
                                    call.argument<String>("muteActionLabel").orEmpty(),
                                stopScreenShareActionLabel =
                                    call.argument<String>("stopScreenShareActionLabel").orEmpty(),
                                disconnectActionLabel =
                                    call.argument<String>("disconnectActionLabel").orEmpty(),
                                isMuted = call.argument<Boolean>("isMuted") ?: false,
                                isSharingScreen =
                                    call.argument<Boolean>("isSharingScreen") ?: false,
                                includeMediaProjection =
                                    call.argument<Boolean>("includeMediaProjection") ?: false,
                                sessionEpoch =
                                    call.argument<Number>("sessionEpoch")?.toInt() ?: 0,
                            )
                        pendingSessionSyncResults.add(result)
                        FlSpeakSessionService.sync(applicationContext, payload) { ok ->
                            runOnUiThread {
                                if (pendingSessionSyncResults.remove(result)) {
                                    result.success(ok)
                                }
                            }
                        }
                    }
                    "stopSession" -> {
                        FlSpeakSessionService.stop(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(messenger, "flspeak/session_service_actions")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sessionActionListener?.let { FlSpeakSessionService.clearActionListener(it) }
                    sessionActionListener = null
                    sessionActionSink = events
                    val sink = events ?: return
                    val listener: (String) -> Unit = { action ->
                        runOnUiThread {
                            if (sessionActionSink === sink) {
                                sink.success(action)
                            }
                        }
                    }
                    sessionActionListener = listener
                    FlSpeakSessionService.setActionListener(listener)
                }

                override fun onCancel(arguments: Any?) {
                    sessionActionSink = null
                    sessionActionListener?.let { FlSpeakSessionService.clearActionListener(it) }
                    sessionActionListener = null
                }
            })
    }

    private fun registerFilesChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flspeak/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveDownload") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                if (path == null || name.isNullOrEmpty() || name.contains('/') || name.contains('\\') || name == "." || name == "..") {
                    result.error("invalid_file", "Invalid download file", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                                put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/FlSpeak")
                                put(MediaStore.MediaColumns.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                ?: error("Cannot create download")
                            try {
                                contentResolver.openOutputStream(uri)?.use { output ->
                                    File(path).inputStream().use { input -> input.copyTo(output) }
                                } ?: error("Cannot write download")
                                values.clear()
                                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                                check(contentResolver.update(uri, values, null, null) > 0) { "Cannot publish download" }
                            } catch (error: Exception) {
                                contentResolver.delete(uri, null, null)
                                throw error
                            }
                            uri.toString()
                        } else {
                            val directory = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                                ?: error("Downloads unavailable")
                            val target = File.createTempFile("flspeak-", "-$name", directory)
                            try {
                                File(path).inputStream().use { input -> target.outputStream().use { output -> input.copyTo(output) } }
                            } catch (error: Exception) {
                                target.delete()
                                throw error
                            }
                            target.absolutePath
                        }
                        runOnUiThread { result.success(saved) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("save_failed", error.message, null) }
                    }
                }.start()
            }
    }

    private fun registerNetworkDnsChannels(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "flspeak/network_dns")
            .setMethodCallHandler { call, result ->
                if (call.method == "getDnsServers") {
                    result.success(currentDnsServers())
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(messenger, "flspeak/network_dns_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    unregisterDnsCallback()
                    val sink = events ?: return
                    val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                    if (manager == null) {
                        sink.success(emptyList<String>())
                        return
                    }
                    var lastSent: List<String>? = null
                    fun emitIfChanged(servers: List<String>) {
                        runOnUiThread {
                            if (dnsCallback == null) return@runOnUiThread
                            if (lastSent != servers) {
                                lastSent = servers
                                sink.success(servers)
                            }
                        }
                    }
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onLinkPropertiesChanged(
                            network: Network,
                            linkProperties: LinkProperties,
                        ) {
                            emitIfChanged(extractDnsServers(linkProperties))
                        }

                        override fun onLost(network: Network) {
                            emitIfChanged(currentDnsServers())
                        }
                    }
                    dnsCallback = callback
                    try {
                        manager.registerDefaultNetworkCallback(callback)
                        emitIfChanged(currentDnsServers())
                    } catch (_: SecurityException) {
                        dnsCallback = null
                        sink.success(emptyList<String>())
                    }
                }

                override fun onCancel(arguments: Any?) {
                    unregisterDnsCallback()
                }
            })
    }

    private fun unregisterDnsCallback() {
        val callback = dnsCallback ?: return
        dnsCallback = null
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        try {
            manager.unregisterNetworkCallback(callback)
        } catch (_: IllegalArgumentException) {
        }
    }

    private fun currentDnsServers(): List<String> {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return emptyList()
        return try {
            val network = manager.activeNetwork ?: return emptyList()
            extractDnsServers(manager.getLinkProperties(network))
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    private fun extractDnsServers(linkProperties: LinkProperties?): List<String> {
        if (linkProperties == null) return emptyList()
        return linkProperties.dnsServers
            .asSequence()
            .filter { !it.isLinkLocalAddress && !it.isAnyLocalAddress && !it.isMulticastAddress }
            .mapNotNull { it.hostAddress?.substringBefore('%') }
            .distinct()
            .toList()
    }
}
