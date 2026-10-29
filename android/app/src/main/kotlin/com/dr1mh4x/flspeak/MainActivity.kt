package com.dr1mh4x.flspeak

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
