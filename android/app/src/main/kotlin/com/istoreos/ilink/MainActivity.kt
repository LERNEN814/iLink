package com.istoreos.ilink

import android.content.ContentValues
import android.content.pm.PackageManager
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
