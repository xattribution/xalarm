package com.xattribution.xalarm

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.xattribution.xalarm.widgets.WidgetStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var previewPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "xalarm/system_sounds",
        )
        channel?.setMethodCallHandler { call, result ->
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
                "preview" -> {
                    val source = call.argument<String>("source")
                    if (source == null) {
                        result.error("bad_args", "source is required", null)
                    } else {
                        try {
                            startPreview(source)
                            result.success(true)
                        } catch (e: Exception) {
                            stopPreview(notify = false)
                            result.error("preview_failed", e.message, null)
                        }
                    }
                }
                "stopPreview" -> {
                    stopPreview(notify = false)
                    result.success(true)
                }
                "getInitialTab" -> {
                    result.success(intent?.getIntExtra("xalarm_tab", -1) ?: -1)
                    intent?.removeExtra("xalarm_tab")
                }
                "syncWidgets" -> {
                    val json = call.argument<String>("json")
                    if (json == null) {
                        result.error("bad_args", "json is required", null)
                    } else {
                        WidgetStore.save(this, json)
                        result.success(true)
                    }
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("bad_args", "url is required", null)
                    } else {
                        try {
                            startActivity(
                                android.content.Intent(
                                    android.content.Intent.ACTION_VIEW,
                                    Uri.parse(url),
                                ),
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("open_failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // A widget tap while the app is already running: tell Flutter which
        // tab to show.
        val tab = intent.getIntExtra("xalarm_tab", -1)
        if (tab >= 0) {
            channel?.invokeMethod("openTab", tab)
            intent.removeExtra("xalarm_tab")
        }
    }

    override fun onPause() {
        stopPreview(notify = true)
        super.onPause()
    }

    override fun onDestroy() {
        stopPreview(notify = false)
        super.onDestroy()
    }

    // --- preview ---

    /**
     * Plays any sound source the app knows about: the 'system' default alarm
     * sound, a bundled Flutter asset ("assets/…"), a content:// device sound,
     * or an absolute file path. One preview at a time; completion is reported
     * back to Dart so the UI can reset its play indicator.
     */
    private fun startPreview(source: String) {
        stopPreview(notify = false)
        val player = MediaPlayer()
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        when {
            source == "system" -> player.setDataSource(
                this,
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            )
            source.startsWith("content://") ->
                player.setDataSource(this, Uri.parse(source))
            source.startsWith("assets/") -> {
                val afd = assets.openFd("flutter_assets/$source")
                afd.use {
                    player.setDataSource(it.fileDescriptor, it.startOffset, it.length)
                }
            }
            else -> player.setDataSource(source)
        }
        player.isLooping = false
        player.setOnPreparedListener { it.start() }
        player.setOnCompletionListener { stopPreview(notify = true) }
        player.setOnErrorListener { _, _, _ ->
            stopPreview(notify = true)
            true
        }
        player.prepareAsync()
        previewPlayer = player
    }

    private fun stopPreview(notify: Boolean) {
        previewPlayer?.let { player ->
            try {
                if (player.isPlaying) player.stop()
            } catch (_: Exception) {
            }
            player.release()
        }
        previewPlayer = null
        if (notify) {
            Handler(Looper.getMainLooper()).post {
                channel?.invokeMethod("previewEnded", null)
            }
        }
    }

    // --- system sound catalogue ---

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
