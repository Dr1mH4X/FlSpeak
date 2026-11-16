package com.dr1mh4x.flspeak

import android.content.ContentValues
import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var dnsCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerFilesChannel(flutterEngine)
        registerNetworkDnsChannels(flutterEngine)
    }

    override fun onDestroy() {
        unregisterDnsCallback()
        super.onDestroy()
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
