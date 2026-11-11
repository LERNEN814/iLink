package com.istoreos.ilink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelId = "ilink-transfers"
    private var nextNotificationId = 4100

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ilink/notify")
            .setMethodCallHandler { call, result ->
                val manager =
                    getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                ensureChannel(manager)
                when (call.method) {
                    "progress" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                4102,
                            )
                        }
                        val id = call.argument<Int>("id") ?: nextNotificationId++
                        val title = call.argument<String>("title") ?: "传输"
                        val text = call.argument<String>("text") ?: ""
                        val progress = call.argument<Int>("progress") ?: 0
                        val max = (call.argument<Int>("max") ?: 100).coerceAtLeast(1)
                        val builder =
                            Notification
                                .Builder(this, channelId)
                                .setSmallIcon(android.R.drawable.stat_sys_download)
                                .setContentTitle(title)
                                .setContentText(text)
                                .setOnlyAlertOnce(true)
                                .setOngoing(true)
                                .setProgress(max, progress, false)
                        manager.notify(id, builder.build())
                        result.success(id)
                    }

                    "done" -> {
                        val id = call.argument<Int>("id") ?: nextNotificationId++
                        val title = call.argument<String>("title") ?: "传输完成"
                        val text = call.argument<String>("text") ?: ""
                        val failed = call.argument<Boolean>("failed") ?: false
                        val builder =
                            Notification
                                .Builder(this, channelId)
                                .setSmallIcon(
                                    if (failed) {
                                        android.R.drawable.stat_notify_error
                                    } else {
                                        android.R.drawable.stat_sys_download_done
                                    },
                                ).setContentTitle(title)
                                .setContentText(text)
                                .setAutoCancel(true)
                        manager.notify(id, builder.build())
                        result.success(id)
                    }

                    "cancel" -> {
                        val id = call.argument<Int>("id")
                        if (id != null) manager.cancel(id)
                        result.success(null)
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ilink/save")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveDownloaded") {
                    return@setMethodCallHandler result.notImplemented()
                }
                val tempPath = call.argument<String>("tempPath")
                val name = call.argument<String>("name")
                val mime = call.argument<String>("mime")
                if (tempPath == null || name == null) {
                    return@setMethodCallHandler result.error("bad_args", "缺少参数", null)
                }
                Thread {
                    try {
                        val location = saveToDownloads(File(tempPath), name, mime ?: "application/octet-stream")
                        runOnUiThread { result.success(location) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("save_failed", error.message, null) }
                    }
                }.start()
            }
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (manager.getNotificationChannel(channelId) != null) return
        manager.createNotificationChannel(
            NotificationChannel(channelId, "传输任务", NotificationManager.IMPORTANCE_LOW).apply {
                description = "下载与更新进度"
                setShowBadge(false)
            },
        )
    }

    // / Android 10+ writes into the public Downloads folder through MediaStore,
    // / no storage permission required. Older releases fall back to direct
    // / access behind WRITE_EXTERNAL_STORAGE.
    private fun saveToDownloads(
        temp: File,
        name: String,
        mime: String,
    ): String {
        if (Build.VERSION.SDK_INT >= 29) {
            val values =
                ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/idownload")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            val uri =
                contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("无法写入公共下载目录")
            contentResolver.openOutputStream(uri)!!.use { output ->
                temp.inputStream().use { input -> input.copyTo(output) }
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            temp.delete()
            return "Download/idownload/$name"
        }
        if (checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE), 4101)
            throw IllegalStateException("需要存储权限，请授权后重试")
        }
        val dir =
            File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "idownload",
            ).apply { mkdirs() }
        var target = File(dir, name)
        var suffix = 1
        val dot = name.lastIndexOf('.')
        while (target.exists()) {
            val stem = if (dot > 0) name.substring(0, dot) else name
            val ext = if (dot > 0) name.substring(dot) else ""
            target = File(dir, "$stem ($suffix)$ext")
            suffix++
        }
        target.outputStream().use { output ->
            temp.inputStream().use { input -> input.copyTo(output) }
        }
        temp.delete()
        return target.absolutePath
    }
}
