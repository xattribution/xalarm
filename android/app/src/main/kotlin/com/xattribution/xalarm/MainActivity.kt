package com.xattribution.xalarm

import android.media.RingtoneManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "xalarm/system_sounds",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> result.success(listSystemSounds())
                "copyToFile" -> {
                    val uri = call.argument<String>("uri")
                    val destDir = call.argument<String>("destDir")
                    val title = call.argument<String>("title") ?: "system-sound"
                    if (uri == null || destDir == null) {
                        result.error("bad_args", "uri and destDir are required", null)
                    } else {
                        copySoundToFile(uri, destDir, title, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** All system alarm / ringtone / notification sounds as title+uri+kind. */
    private fun listSystemSounds(): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        val kinds = listOf(
            RingtoneManager.TYPE_ALARM to "alarm",
            RingtoneManager.TYPE_RINGTONE to "ringtone",
            RingtoneManager.TYPE_NOTIFICATION to "notification",
        )
        for ((type, kind) in kinds) {
            try {
                val manager = RingtoneManager(this)
                manager.setType(type)
                val cursor = manager.cursor
                while (cursor.moveToNext()) {
                    val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                    val uri = manager.getRingtoneUri(cursor.position)
                    out.add(
                        mapOf(
                            "title" to (title ?: "Unknown"),
                            "uri" to uri.toString(),
                            "kind" to kind,
                        ),
                    )
                }
            } catch (_: Exception) {
                // A missing provider for one kind shouldn't hide the others.
            }
        }
        return out
    }

    /**
     * Copies a system sound (content:// URI) into a real file inside the
     * app's ringtone library, because the alarm player needs a file path.
     * Runs off the main thread; replies with the created file's path.
     */
    private fun copySoundToFile(
        uriString: String,
        destDir: String,
        title: String,
        result: MethodChannel.Result,
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        thread {
            try {
                val uri = Uri.parse(uriString)
                val ext = when (contentResolver.getType(uri)) {
                    "audio/mpeg" -> ".mp3"
                    "audio/x-wav", "audio/wav" -> ".wav"
                    "audio/aac", "audio/mp4", "audio/x-m4a" -> ".m4a"
                    "audio/flac" -> ".flac"
                    else -> ".ogg" // AOSP system sounds are ogg
                }
                val safeName = title
                    .replace(Regex("[^A-Za-z0-9 _-]"), "")
                    .trim()
                    .ifEmpty { "system-sound" }
                val dir = File(destDir)
                if (!dir.exists()) dir.mkdirs()
                var dest = File(dir, "$safeName$ext")
                var n = 1
                while (dest.exists()) {
                    dest = File(dir, "$safeName-$n$ext")
                    n++
                }
                contentResolver.openInputStream(uri).use { input ->
                    if (input == null) throw IllegalStateException("Cannot open $uriString")
                    FileOutputStream(dest).use { output -> input.copyTo(output) }
                }
                mainHandler.post { result.success(dest.absolutePath) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("copy_failed", e.message ?: "copy failed", null)
                }
            }
        }
    }
}
