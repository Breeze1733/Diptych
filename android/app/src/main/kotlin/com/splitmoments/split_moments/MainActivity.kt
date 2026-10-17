package com.splitmoments.split_moments

import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Build
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
            when (call.method) {
                "scanFile" -> {
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
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER ?: "")
                }
                else -> result.notImplemented()
            }
        }

        // 2. APK installation channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
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
                            ?: throw IllegalStateException("PowerManager is unavailable")
                        if (wakeLock == null) {
                            wakeLock = powerManager.newWakeLock(
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
                else -> result.notImplemented()
            }
        }

        // 4. Foreground Service Channel (在通知栏展示传输任务，降低后台受限风险)
        val FOREGROUND_CHANNEL = "com.splitmoments.split_moments/foreground_service"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOREGROUND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "Diptych"
                    val content = call.argument<String>("content") ?: "正在传输数据..."
                    val maxProgress = (call.argument<Number>("maxProgress"))?.toInt() ?: 0
                    val progress = (call.argument<Number>("progress"))?.toInt() ?: 0
                    try {
                        TransferForegroundService.startService(context, title, content, maxProgress, progress)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FOREGROUND_SERVICE_ERROR", e.message, null)
                    }
                }
                "update" -> {
                    val title = call.argument<String>("title") ?: "Diptych"
                    val content = call.argument<String>("content") ?: "正在传输数据..."
                    val maxProgress = (call.argument<Number>("maxProgress"))?.toInt() ?: 0
                    val progress = (call.argument<Number>("progress"))?.toInt() ?: 0
                    try {
                        TransferForegroundService.updateProgress(context, title, content, maxProgress, progress)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FOREGROUND_SERVICE_ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        TransferForegroundService.stopService(context)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FOREGROUND_SERVICE_ERROR", e.message, null)
                    }
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
