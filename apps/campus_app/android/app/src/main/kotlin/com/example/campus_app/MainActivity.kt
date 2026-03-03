package com.example.campus_app

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val batteryChannel = "campus_app/battery"
    private val cookieChannel  = "campus_app/cookie_manager"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 电池优化通道 ──────────────────────────────────────────
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
                    val intent = android.content.Intent(
                        android.provider.Settings
                            .ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                    ).apply {
                        data = android.net.Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "openMiuiAutostart" -> {
                    try {
                        val intent = android.content.Intent().apply {
                            component = android.content.ComponentName(
                                "com.miui.securitycenter",
                                "com.miui.permcenter.autostart.AutoStartManagementActivity"
                            )
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        openAppSettings(result)
                    }
                }
                "checkMiuiAutostart" -> result.success(null)
                "openBatterySettings" -> openAppSettings(result)
                else -> result.notImplemented()
            }
        }

        // ── Cookie 读取通道（供 WebView 登录提取 JSESSIONID 使用）──
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            cookieChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("INVALID_ARG", "url 参数缺失", null)
                        return@setMethodCallHandler
                    }
                    val manager = CookieManager.getInstance()
                    manager.flush() // 确保内存 Cookie 已落盘
                    val cookies = manager.getCookie(url) ?: ""
                    android.util.Log.d("CookieChannel", "getCookies($url) => $cookies")
                    result.success(cookies)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        val intent = android.content.Intent(
            android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
        ).apply {
            data = android.net.Uri.parse("package:$packageName")
        }
        startActivity(intent)
        result.success(null)
    }
}