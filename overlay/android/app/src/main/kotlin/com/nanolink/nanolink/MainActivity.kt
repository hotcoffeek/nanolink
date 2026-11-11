package com.nanolink.nanolink

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.graphics.Bitmap
import android.media.ThumbnailUtils
import java.io.ByteArrayOutputStream
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /** Эскизы считаем в 3 потока, а не по потоку на каждую плитку: на слабых телефонах так не лагает. */
    private val thumbPool: java.util.concurrent.ExecutorService = java.util.concurrent.Executors.newFixedThreadPool(3)

    companion object {
        /** Канал нужен приёмнику кнопок уведомления «Принять / Отклонить». */
        @JvmStatic
        var chanRef: MethodChannel? = null
    }

    private var chan: MethodChannel? = null
    private val pending = ArrayList<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShare(intent)
    }

    /** Intent, открывающий папку в файловом менеджере (через DocumentsContract). */
    private fun folderIntent(path: String): Intent {
        var vol = "primary"
        var rel = path
        if (path.startsWith("/storage/emulated/0")) {
            rel = path.removePrefix("/storage/emulated/0")
        } else if (path.startsWith("/sdcard")) {
            rel = path.removePrefix("/sdcard")
        } else if (path.startsWith("/storage/")) {
            val rest = path.removePrefix("/storage/")
            val i = rest.indexOf('/')
            vol = if (i < 0) rest else rest.substring(0, i)
            rel = if (i < 0) "" else rest.substring(i)
        }
        rel = rel.trim('/')
        val uri = android.provider.DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "$vol:$rel")
        val i = Intent(Intent.ACTION_VIEW)
        i.setDataAndType(uri, "vnd.android.document/directory")
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return i
    }

    private fun resolveShared(uri: Uri): String? {
        if (uri.scheme == "file") return uri.path
        try {
            contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(MediaStore.MediaColumns.DATA)
                    if (i >= 0) {
                        val p = c.getString(i)
                        if (p != null && File(p).exists()) return p
                    }
                }
            }
        } catch (e: Exception) {
        }
        try {
            var name = "file"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (i >= 0) name = c.getString(i) ?: "file"
                }
            }
            val dir = File(cacheDir, "nl_share")
            dir.mkdirs()
            var out = File(dir, name)
            var n = 1
            while (out.exists()) {
                out = File(dir, "${n}_$name")
                n++
            }
            contentResolver.openInputStream(uri)?.use { inp -> out.outputStream().use { inp.copyTo(it) } }
            return out.absolutePath
        } catch (e: Exception) {
            return null
        }
    }

    @Suppress("DEPRECATION")
    private fun handleShare(i: Intent?) {
        if (i == null) return
        val act = i.action
        if (act != Intent.ACTION_SEND && act != Intent.ACTION_SEND_MULTIPLE) return
        val uris = ArrayList<Uri>()
        if (act == Intent.ACTION_SEND) {
            val u = i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (u != null) uris.add(u)
        } else {
            val l = i.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (l != null) uris.addAll(l)
        }
        val text = i.getStringExtra(Intent.EXTRA_TEXT)
        Thread {
            val paths = ArrayList<String>()
            for (u in uris) {
                val p = resolveShared(u)
                if (p != null) paths.add(p)
            }
            if (uris.isEmpty() && !text.isNullOrEmpty()) {
                try {
                    val dir = File(cacheDir, "nl_share")
                    dir.mkdirs()
                    val f = File(dir, "text_" + System.currentTimeMillis() + ".txt")
                    f.writeText(text)
                    paths.add(f.absolutePath)
                } catch (e: Exception) {
                }
            }
            runOnUiThread {
                pending.addAll(paths)
                chan?.invokeMethod("sharedReady", null)
            }
        }.start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nanolink/native")
        chan = ch
        chanRef = ch
        SmbBridge.register(flutterEngine.dartExecutor.binaryMessenger)
        ch.setMethodCallHandler { call, result ->
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
                        val once = call.argument<Boolean>("once") ?: false
                        val prefs = getSharedPreferences("nl_native", Context.MODE_PRIVATE)
                        val skip = once && prefs.getBoolean("batAsked", false)
                        if (once) prefs.edit().putBoolean("batAsked", true).apply()
                        if (!skip && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !pm.isIgnoringBatteryOptimizations(packageName)) {
                            try {
                                startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                            } catch (e: Exception) {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            }
                        }
                        result.success(true)
                    }
                    "batteryExempt" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.M || pm.isIgnoringBatteryOptimizations(packageName))
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
                    "notify" -> {
                        val title = call.argument<String>("title") ?: "NanoLink"
                        val text = call.argument<String>("text") ?: ""
                        val id = call.argument<Int>("id") ?: 1
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        if (Build.VERSION.SDK_INT >= 26) {
                            nm.createNotificationChannel(android.app.NotificationChannel("nl_recv", "NanoLink", android.app.NotificationManager.IMPORTANCE_HIGH))
                        }
                        val pi = android.app.PendingIntent.getActivity(
                            this, 0,
                            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK),
                            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT)
                        val b = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(this, "nl_recv") else android.app.Notification.Builder(this)
                        b.setContentTitle(title).setContentText(text).setSmallIcon(applicationInfo.icon).setContentIntent(pi).setAutoCancel(true)
                        nm.notify(id, b.build())
                        result.success(true)
                    }
                    "notifyAsk" -> {
                        val title = call.argument<String>("title") ?: "NanoLink"
                        val text = call.argument<String>("text") ?: ""
                        val yesLabel = call.argument<String>("yes") ?: "OK"
                        val noLabel = call.argument<String>("no") ?: "No"
                        val id = call.argument<Int>("id") ?: 2
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        if (Build.VERSION.SDK_INT >= 26) {
                            nm.createNotificationChannel(android.app.NotificationChannel("nl_recv", "NanoLink", android.app.NotificationManager.IMPORTANCE_HIGH))
                        }
                        val flags = android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
                        val open = android.app.PendingIntent.getActivity(
                            this, 0,
                            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK),
                            flags)
                        val yes = android.app.PendingIntent.getBroadcast(
                            this, 101,
                            Intent(this, RecvActionReceiver::class.java).setAction("nanolink.RECV_YES").putExtra("id", id),
                            flags)
                        val no = android.app.PendingIntent.getBroadcast(
                            this, 102,
                            Intent(this, RecvActionReceiver::class.java).setAction("nanolink.RECV_NO").putExtra("id", id),
                            flags)
                        val b = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(this, "nl_recv") else android.app.Notification.Builder(this)
                        b.setContentTitle(title).setContentText(text).setSmallIcon(applicationInfo.icon)
                            .setContentIntent(open).setAutoCancel(true)
                            .setVisibility(android.app.Notification.VISIBILITY_PUBLIC)
                            .addAction(android.app.Notification.Action.Builder(null, yesLabel, yes).build())
                            .addAction(android.app.Notification.Action.Builder(null, noLabel, no).build())
                        if (Build.VERSION.SDK_INT >= 26) b.setTimeoutAfter(20000)
                        @Suppress("DEPRECATION")
                        if (Build.VERSION.SDK_INT < 26) b.setPriority(android.app.Notification.PRIORITY_HIGH)
                        nm.notify(id, b.build())
                        result.success(true)
                    }
                    "cancelNotify" -> {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        nm.cancel(call.argument<Int>("id") ?: 2)
                        result.success(true)
                    }
                    "storageStats" -> {
                        val st = android.os.StatFs(Environment.getExternalStorageDirectory().absolutePath)
                        result.success(arrayListOf(st.totalBytes, st.availableBytes))
                    }
                    "takeShared" -> {
                        val l = ArrayList(pending)
                        pending.clear()
                        result.success(l)
                    }
                    "hasMedia" -> {
                        val perms = if (Build.VERSION.SDK_INT >= 33)
                            arrayOf(android.Manifest.permission.READ_MEDIA_IMAGES, android.Manifest.permission.READ_MEDIA_VIDEO)
                        else arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE)
                        var ok = true
                        for (p in perms) if (checkSelfPermission(p) != android.content.pm.PackageManager.PERMISSION_GRANTED) ok = false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) ok = true
                        result.success(ok)
                    }
                    "requestMedia" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(arrayOf(
                                android.Manifest.permission.READ_MEDIA_IMAGES,
                                android.Manifest.permission.READ_MEDIA_VIDEO,
                                android.Manifest.permission.READ_MEDIA_AUDIO), 9)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            requestPermissions(arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE), 9)
                        }
                        result.success(true)
                    }
                    "openAppSettings" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(true)
                    }
                    "queryMedia" -> {
                        val kind = call.argument<String>("kind") ?: "images"
                        val uri = when (kind) {
                            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                            else -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        }
                        val proj = arrayOf(
                            MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.SIZE,
                            MediaStore.MediaColumns.DATE_MODIFIED, MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
                        val out = ArrayList<HashMap<String, Any>>()
                        contentResolver.query(uri, proj, null, null, MediaStore.MediaColumns.DATE_MODIFIED + " DESC")?.use { c ->
                            val iD = c.getColumnIndex(MediaStore.MediaColumns.DATA)
                            val iS = c.getColumnIndex(MediaStore.MediaColumns.SIZE)
                            val iM = c.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
                            val iB = c.getColumnIndex(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
                            while (c.moveToNext() && out.size < 60000) {
                                val p = c.getString(iD) ?: continue
                                val m = HashMap<String, Any>()
                                m["p"] = p
                                m["s"] = c.getLong(iS)
                                m["m"] = c.getLong(iM) * 1000
                                m["b"] = c.getString(iB) ?: ""
                                out.add(m)
                            }
                        }
                        result.success(out)
                    }
                    "thumb" -> {
                        val path = call.argument<String>("path") ?: ""
                        val size = call.argument<Int>("size") ?: 256
                        thumbPool.execute {
                            var bytes: ByteArray? = null
                            try {
                                val low = path.lowercase()
                                val isVideo = low.endsWith(".mp4") || low.endsWith(".mkv") || low.endsWith(".3gp") || low.endsWith(".webm") ||
                                    low.endsWith(".mov") || low.endsWith(".avi") || low.endsWith(".m4v") || low.endsWith(".ts") || low.endsWith(".wmv")
                                val bmp: Bitmap? = if (Build.VERSION.SDK_INT >= 29) {
                                    if (isVideo) ThumbnailUtils.createVideoThumbnail(File(path), android.util.Size(size, size), null)
                                    else ThumbnailUtils.createImageThumbnail(File(path), android.util.Size(size, size), null)
                                } else {
                                    @Suppress("DEPRECATION")
                                    if (isVideo) ThumbnailUtils.createVideoThumbnail(path, MediaStore.Video.Thumbnails.MINI_KIND) else null
                                }
                                if (bmp != null) {
                                    val bo = ByteArrayOutputStream()
                                    bmp.compress(Bitmap.CompressFormat.JPEG, 80, bo)
                                    bytes = bo.toByteArray()
                                }
                            } catch (e: Exception) {
                            }
                            runOnUiThread { result.success(bytes) }
                        }
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
                    "listFolderApps" -> {
                        val path = call.argument<String>("path") ?: "/storage/emulated/0"
                        val out = ArrayList<Map<String, String>>()
                        val seen = HashSet<String>()
                        for (ri in packageManager.queryIntentActivities(folderIntent(path), 0)) {
                            val pkg = ri.activityInfo.packageName
                            if (pkg == packageName || !seen.add(pkg)) continue
                            out.add(mapOf("pkg" to pkg, "label" to ri.loadLabel(packageManager).toString()))
                        }
                        result.success(out)
                    }
                    "openFolder" -> {
                        val path = call.argument<String>("path") ?: ""
                        val pkg = call.argument<String>("pkg") ?: ""
                        val i = folderIntent(path)
                        if (pkg.isNotEmpty()) i.setPackage(pkg)
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
