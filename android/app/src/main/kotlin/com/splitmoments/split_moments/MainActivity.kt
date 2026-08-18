package com.splitmoments.split_moments

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val MEDIA_CHANNEL = "com.splitmoments.split_moments/media_scanner"
    private val DOWNLOAD_CHANNEL = "com.splitmoments.split_moments/downloader"
    private val WAKELOCK_CHANNEL = "com.splitmoments.split_moments/wakelock"

    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Android 13+ (API 33+) 自动申请通知栏运行时权限，确保前台服务通知正常显示
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }

        // 1. Media Scanner Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    MediaScannerConnection.scanFile(
                        context,
                        arrayOf(path),
                        null
                    ) { _, _ -> }
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "path is required", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // 2. DownloadManager Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL).setMethodCallHandler { call, result ->
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
            if (dm == null) {
                result.error("UNAVAILABLE", "DownloadManager is not available on this device", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "startDownload" -> {
                    val url = call.argument<String>("url")
                    val title = call.argument<String>("title") ?: "Diptych 更新"
                    val desc = call.argument<String>("description") ?: "正在下载最新安装包..."
                    val fileName = call.argument<String>("fileName") ?: "diptych_update.apk"

                    if (url.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "url is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        // 预先清理同名旧 APK 文件
                        val downloadDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                        if (downloadDir != null) {
                            val targetFile = File(downloadDir, fileName)
                            if (targetFile.exists()) {
                                targetFile.delete()
                            }
                        }

                        val request = DownloadManager.Request(Uri.parse(url)).apply {
                            setTitle(title)
                            setDescription(desc)
                            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                            setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, fileName)
                            setMimeType("application/vnd.android.package-archive")
                        }
                        val downloadId = dm.enqueue(request)
                        result.success(downloadId)
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_ERROR", e.message, null)
                    }
                }
                "getDownloadStatus" -> {
                    val downloadId = (call.argument<Number>("downloadId"))?.toLong()
                    if (downloadId == null) {
                        result.error("INVALID_ARGUMENT", "downloadId is required", null)
                        return@setMethodCallHandler
                    }

                    val query = DownloadManager.Query().setFilterById(downloadId)
                    var cursor: Cursor? = null
                    try {
                        cursor = dm.query(query)
                        if (cursor != null && cursor.moveToFirst()) {
                            val statusIdx = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                            val downloadedIdx = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                            val totalIdx = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                            val localUriIdx = cursor.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)

                            val statusVal = if (statusIdx >= 0) cursor.getInt(statusIdx) else -1
                            val downloaded = if (downloadedIdx >= 0) cursor.getLong(downloadedIdx) else 0L
                            val total = if (totalIdx >= 0) cursor.getLong(totalIdx) else 0L
                            val localUriStr = if (localUriIdx >= 0) cursor.getString(localUriIdx) else null

                            val statusStr = when (statusVal) {
                                DownloadManager.STATUS_RUNNING -> "running"
                                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                                DownloadManager.STATUS_FAILED -> "failed"
                                DownloadManager.STATUS_PAUSED -> "paused"
                                DownloadManager.STATUS_PENDING -> "pending"
                                else -> "unknown"
                            }

                            var filePath: String? = null
                            if (localUriStr != null) {
                                val uri = Uri.parse(localUriStr)
                                filePath = if (uri.scheme == "file") uri.path else {
                                    val downloadDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                                    if (downloadDir != null) File(downloadDir, "diptych_update.apk").absolutePath else null
                                }
                            } else {
                                val downloadDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                                if (downloadDir != null) {
                                    val file = File(downloadDir, "diptych_update.apk")
                                    if (file.exists()) filePath = file.absolutePath
                                }
                            }

                            val map = mapOf(
                                "status" to statusStr,
                                "downloadedBytes" to downloaded,
                                "totalBytes" to total,
                                "filePath" to filePath
                            )
                            result.success(map)
                        } else {
                            result.success(mapOf("status" to "unknown"))
                        }
                    } catch (e: Exception) {
                        result.error("QUERY_ERROR", e.message, null)
                    } finally {
                        cursor?.close()
                    }
                }
                "removeDownload" -> {
                    val downloadId = (call.argument<Number>("downloadId"))?.toLong()
                    if (downloadId != null && downloadId > 0) {
                        try {
                            dm.remove(downloadId)
                        } catch (_: Exception) {}
                    }
                    // 同时做物理文件兜底扫描清理
                    try {
                        val downloadDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                        if (downloadDir != null && downloadDir.exists()) {
                            downloadDir.listFiles { file -> file.name.endsWith(".apk") }?.forEach { apk ->
                                apk.delete()
                            }
                        }
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "filePath is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist: $filePath", null)
                            return@setMethodCallHandler
                        }

                        // 检查 Android 8.0+ 是否允许安装未知来源应用
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            if (!packageManager.canRequestPackageInstalls()) {
                                val manageIntent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    android.net.Uri.parse("package:$packageName")
                                ).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(manageIntent)
                                result.error("NEED_PERMISSION", "请在系统设置中允许 Diptych 安装应用", null)
                                return@setMethodCallHandler
                            }
                        }

                        val uri = FileProvider.getUriForFile(
                            this,
                            "${packageName}.fileprovider",
                            file
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 3. WakeLock Channel (CPU 防休眠锁)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKELOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    val timeoutMs = (call.argument<Number>("timeoutMs"))?.toLong() ?: 600000L
                    try {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        if (wakeLock == null) {
                            wakeLock = powerManager?.newWakeLock(
                                PowerManager.PARTIAL_WAKE_LOCK,
                                "Diptych:UploadWakeLock"
                            )
                            wakeLock?.setReferenceCounted(false)
                        }
                        wakeLock?.acquire(timeoutMs)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WAKELOCK_ERROR", e.message, null)
                    }
                }
                "release" -> {
                    try {
                        if (wakeLock?.isHeld == true) {
                            wakeLock?.release()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WAKELOCK_ERROR", e.message, null)
                    }
                }
                "isHeld" -> {
                    result.success(wakeLock?.isHeld == true)
                }
                else -> result.notImplemented()
            }
        }

        // 4. Foreground Service Channel (前台保活服务：获取 Linux 内核网络豁免权，防止切后台断流)
        val FOREGROUND_CHANNEL = "com.splitmoments.split_moments/foreground_service"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOREGROUND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "Diptych"
                    val content = call.argument<String>("content") ?: "正在传输数据..."
                    val maxProgress = (call.argument<Number>("maxProgress"))?.toInt() ?: 0
                    val progress = (call.argument<Number>("progress"))?.toInt() ?: 0
                    TransferForegroundService.startService(context, title, content, maxProgress, progress)
                    result.success(true)
                }
                "update" -> {
                    val title = call.argument<String>("title") ?: "Diptych"
                    val content = call.argument<String>("content") ?: "正在传输数据..."
                    val maxProgress = (call.argument<Number>("maxProgress"))?.toInt() ?: 0
                    val progress = (call.argument<Number>("progress"))?.toInt() ?: 0
                    TransferForegroundService.updateProgress(context, title, content, maxProgress, progress)
                    result.success(true)
                }
                "stop" -> {
                    TransferForegroundService.stopService(context)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
