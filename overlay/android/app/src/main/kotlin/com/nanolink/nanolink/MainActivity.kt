package com.nanolink.nanolink

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nanolink/native").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startKeepAlive" -> {
                        val bind = call.argument<Boolean>("bind") ?: true
                        val i = Intent(this, KeepAliveService::class.java).putExtra("bind", bind)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
                        result.success(true)
                    }
                    "stopKeepAlive" -> {
                        stopService(Intent(this, KeepAliveService::class.java))
                        result.success(true)
                    }
                    "hasAllFiles" -> {
                        result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager() else true)
                    }
                    "requestAllFiles" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            try {
                                startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName")))
                            } catch (e: Exception) {
                                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                            }
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            requestPermissions(
                                arrayOf(
                                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                                ), 7
                            )
                        }
                        result.success(true)
                    }
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 8)
                        }
                        result.success(true)
                    }
                    "requestBatteryExemption" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !pm.isIgnoringBatteryOptimizations(packageName)) {
                            try {
                                startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                            } catch (e: Exception) {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            }
                        }
                        result.success(true)
                    }
                    "storageRoots" -> {
                        val roots = ArrayList<String>()
                        val primary = Environment.getExternalStorageDirectory().absolutePath
                        roots.add(primary)
                        try {
                            for (d in getExternalFilesDirs(null)) {
                                if (d == null) continue
                                val p = d.absolutePath
                                val idx = p.indexOf("/Android/data")
                                if (idx > 0) {
                                    val root = p.substring(0, idx)
                                    if (root != primary && File(root).exists() && !roots.contains(root)) roots.add(root)
                                }
                            }
                        } catch (_: Exception) {
                        }
                        result.success(roots)
                    }
                    "deviceModel" -> {
                        val m = Build.MODEL ?: "Android"
                        val mf = Build.MANUFACTURER ?: ""
                        result.success(if (m.startsWith(mf, true) || mf.isEmpty()) m else "$mf $m")
                    }
                    "isTv" -> {
                        val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        result.success(ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    "openFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        val mime = call.argument<String>("mime") ?: "*/*"
                        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.fileprovider", File(path))
                        val i = Intent(Intent.ACTION_VIEW)
                        i.setDataAndType(uri, mime)
                        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        try {
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "isTablet" -> {
                        result.success(resources.configuration.smallestScreenWidthDp >= 600)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
    }
}
