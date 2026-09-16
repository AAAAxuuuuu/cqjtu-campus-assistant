package com.example.campus_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.CookieManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val batteryChannel = "campus_app/battery"
    private val cookieChannel = "campus_app/cookie_manager"
    private val appUpdateChannel = "campus_app/app_update"
    private val classReminderChannel = "campus_app/class_reminder"
    private val scheduleWidgetChannel = "campus_app/schedule_widget"
    private val widgetNavigationChannelName = "campus_app/widget_navigation"

    private var widgetNavigationChannel: MethodChannel? = null
    private var pendingWidgetTarget: String? = null
    private var pendingInstallApkPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            batteryChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(POWER_SERVICE)
                            as android.os.PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestIgnoreBatteryOptimizations" -> {
                    val intent = Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                    ).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "openAppSettings" -> {
                    openAppSettings(result)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            cookieChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setCookie" -> {
                    val url = call.argument<String>("url")
                    val cookie = call.argument<String>("cookie")
                    if (url.isNullOrBlank() || cookie.isNullOrBlank()) {
                        result.error(
                            "INVALID_ARG",
                            "url and cookie parameters are required",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    val manager = CookieManager.getInstance()
                    manager.setAcceptCookie(true)
                    manager.setCookie(url, cookie)
                    manager.flush()
                    result.success(null)
                }
                "getCookies" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error(
                            "INVALID_ARG",
                            "url parameter is required",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    val manager = CookieManager.getInstance()
                    manager.flush()
                    val cookies = manager.getCookie(url) ?: ""
                    android.util.Log.d(
                        "CookieChannel",
                        "getCookies($url) => length=${cookies.length}"
                    )
                    result.success(cookies)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appUpdateChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_ARG", "path parameter is required", null)
                        return@setMethodCallHandler
                    }
                    installApk(path, result)
                }
                "checkApkFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    result.success(isApkValid(path))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            classReminderChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleClassReminders" -> {
                    val reminders = call.argument<List<Map<String, Any?>>>("reminders")
                    if (reminders == null) {
                        result.error("INVALID_ARG", "reminders parameter is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        ClassReminderManager.scheduleFromFlutter(this, reminders)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SCHEDULE_FAILED", e.message, null)
                    }
                }
                "cancelClassReminders" -> {
                    try {
                        ClassReminderManager.cancelAll(this)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CANCEL_FAILED", e.message, null)
                    }
                }
                "getLiveReminderCapabilities" -> {
                    result.success(ClassReminderManager.getCapabilities(this))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            scheduleWidgetChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateScheduleWidgets" -> {
                    val courses = call.argument<List<Map<String, Any?>>>("courses")
                    val semesterStartMillis = call.argument<Number>("semesterStartMillis")
                    if (courses == null || semesterStartMillis == null) {
                        result.error(
                            "INVALID_ARG",
                            "courses and semesterStartMillis are required",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        ScheduleWidgetManager.updateFromFlutter(
                            this,
                            courses,
                            semesterStartMillis.toLong(),
                            call.argument<String>("selectedSemester"),
                            call.argument<String>("remark").orEmpty(),
                            call.argument<Number>("totalWeeks")?.toInt() ?: 20
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("WIDGET_UPDATE_FAILED", e.message, null)
                    }
                }
                "clearScheduleWidgets" -> {
                    try {
                        ScheduleWidgetManager.clear(this)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("WIDGET_CLEAR_FAILED", e.message, null)
                    }
                }
                "refreshScheduleWidgets" -> {
                    try {
                        ScheduleWidgetManager.refreshAllWidgets(this)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("WIDGET_REFRESH_FAILED", e.message, null)
                    }
                }
                "updateWidgetBalances" -> {
                    try {
                        ScheduleWidgetManager.updateBalances(
                            this,
                            call.argument<String>("campusCardBalance"),
                            call.argument<String>("electricityBalance")
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("WIDGET_BALANCE_UPDATE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        widgetNavigationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            widgetNavigationChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingWidgetTarget" -> {
                        val target = pendingWidgetTarget ?: extractWidgetTarget(intent)
                        pendingWidgetTarget = null
                        result.success(target)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val target = extractWidgetTarget(intent) ?: return
        pendingWidgetTarget = target
        widgetNavigationChannel?.invokeMethod("widgetTargetChanged", target)
    }

    override fun onResume() {
        super.onResume()
        checkAndResumePendingInstall()
    }

    private fun checkAndResumePendingInstall() {
        val path = pendingInstallApkPath ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            return
        }
        val file = File(path)
        if (file.exists() && file.length() > 0) {
            pendingInstallApkPath = null
            try {
                launchPackageInstaller(file)
            } catch (_: Exception) {}
        }
    }

    private fun isApkValid(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists() || file.length() <= 0) return false
            val archiveInfo = packageManager.getPackageArchiveInfo(path, 0) ?: return false
            archiveInfo.packageName == packageName
        } catch (_: Exception) {
            false
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            if (!file.exists() || file.length() <= 0) {
                result.error("FILE_NOT_FOUND", "APK file does not exist or is empty", null)
                return
            }

            val archiveInfo = packageManager.getPackageArchiveInfo(path, 0)
            if (archiveInfo == null) {
                result.error("APK_CORRUPT", "安装包解析失败，可能文件损坏或未下载完整", null)
                return
            }

            // 检查安装包版本是否低于当前已安装版本（防止降级拦截）
            val currentPackageInfo = try {
                packageManager.getPackageInfo(packageName, 0)
            } catch (_: Exception) {
                null
            }

            if (currentPackageInfo != null) {
                val currentCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    currentPackageInfo.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    currentPackageInfo.versionCode.toLong()
                }
                val newCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    archiveInfo.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    archiveInfo.versionCode.toLong()
                }

                if (newCode < currentCode) {
                    result.error(
                        "VERSION_DOWNGRADE",
                        "安装包版本号 ($newCode) 低于当前已安装版本 ($currentCode)，系统禁止覆盖安装。请先卸载旧版本或安装更高版本。",
                        null
                    )
                    return
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                pendingInstallApkPath = path
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success("permission_required")
                return
            }

            pendingInstallApkPath = null
            launchPackageInstaller(file)
            result.success("install_started")
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message, null)
        }
    }

    private fun launchPackageInstaller(file: File) {
        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS
        ).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
        result.success(null)
    }

    private fun extractWidgetTarget(intent: Intent?): String? {
        return intent
            ?.getStringExtra("widget_target")
            ?.takeIf { it.isNotBlank() }
    }
}
