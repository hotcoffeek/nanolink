package com.nanolink.nanolink

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import jcifs.CIFSContext
import jcifs.config.PropertyConfiguration
import jcifs.context.BaseContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbAuthException
import jcifs.smb.SmbFile
import jcifs.smb.SmbRandomAccessFile
import java.util.Properties
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * SMB через библиотеку jcifs-ng (SMB1 + SMB2/3) - та же основа, что у популярных файловых менеджеров.
 * Нужна для роутеров и NAS, с которыми не справляется Dart-клиент.
 * Канал "nanolink/smb"; путь вида "/шара/папка/файл", "/" - список общих ресурсов.
 */
object SmbBridge {
    private val pool = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private val contexts = ConcurrentHashMap<String, CIFSContext>()
    private val handles = ConcurrentHashMap<Int, SmbRandomAccessFile>()
    private val nextId = AtomicInteger(1)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "nanolink/smb").setMethodCallHandler { call, result ->
            pool.execute {
                try {
                    val r = handle(call)
                    main.post { result.success(r) }
                } catch (e: SmbAuthException) {
                    main.post { result.error("auth", e.message ?: "auth", null) }
                } catch (e: Throwable) {
                    val msg = (e.javaClass.simpleName ?: "Error") + ": " + (e.message ?: "")
                    main.post { result.error("smb", msg, null) }
                }
            }
        }
    }

    private fun key(call: MethodCall): String {
        return (call.argument<String>("host") ?: "") + "|" + (call.argument<Int>("port") ?: 445) + "|" +
            (call.argument<String>("domain") ?: "") + "|" + (call.argument<String>("user") ?: "") + "|" +
            (call.argument<String>("pass") ?: "")
    }

    private fun context(call: MethodCall): CIFSContext {
        val k = key(call)
        val old = contexts[k]
        if (old != null) return old
        val p = Properties()
        p.setProperty("jcifs.smb.client.minVersion", "SMB1")
        p.setProperty("jcifs.smb.client.maxVersion", "SMB311")
        p.setProperty("jcifs.smb.client.responseTimeout", "20000")
        p.setProperty("jcifs.smb.client.soTimeout", "35000")
        p.setProperty("jcifs.smb.client.connTimeout", "8000")
        p.setProperty("jcifs.smb.client.sessionTimeout", "35000")
        p.setProperty("jcifs.resolveOrder", "DNS")
        p.setProperty("jcifs.smb.client.dfs.disabled", "true")
        p.setProperty("jcifs.smb.client.ipcSigningEnforced", "false")
        val base = BaseContext(PropertyConfiguration(p))
        val user = call.argument<String>("user") ?: ""
        val auth = NtlmPasswordAuthenticator(
            call.argument<String>("domain") ?: "",
            if (user.isEmpty()) "guest" else user,
            call.argument<String>("pass") ?: ""
        )
        val ctx = base.withCredentials(auth)
        contexts[k] = ctx
        return ctx
    }

    private fun dropContext(call: MethodCall) {
        val ctx = contexts.remove(key(call))
        try {
            ctx?.close()
        } catch (e: Throwable) {
        }
    }

    /** Файл/папка по пути "/шара/папка/имя". Собираем по частям - так имена с пробелами и # не ломают адрес. */
    private fun file(call: MethodCall, path: String, dir: Boolean): SmbFile {
        val host = call.argument<String>("host") ?: ""
        val port = call.argument<Int>("port") ?: 445
        val root = "smb://" + host + (if (port != 445) ":$port" else "") + "/"
        var f = SmbFile(root, context(call))
        val parts = path.split("/").filter { it.isNotEmpty() }
        for (i in parts.indices) {
            val last = i == parts.size - 1
            f = SmbFile(f, if (last && !dir) parts[i] else parts[i] + "/")
        }
        return f
    }

    private fun cleanName(n: String): String {
        var s = n
        while (s.endsWith("/")) s = s.substring(0, s.length - 1)
        return s
    }

    private fun handle(call: MethodCall): Any? {
        val path = call.argument<String>("path") ?: "/"
        when (call.method) {
            "list" -> {
                val out = ArrayList<Map<String, Any>>()
                val isRoot = path.isEmpty() || path == "/"
                val dir = file(call, path, true)
                val items = dir.listFiles() ?: arrayOf<SmbFile>()
                for (f in items) {
                    val name = cleanName(f.name)
                    if (name.isEmpty() || name == "." || name == "..") continue
                    if (isRoot) {
                        if (name.endsWith("$")) continue
                        var share = true
                        try {
                            share = f.type == SmbFile.TYPE_SHARE
                        } catch (e: Throwable) {
                        }
                        if (!share) continue
                        out.add(mapOf("name" to name, "dir" to true, "size" to 0L, "mtime" to 0L))
                        continue
                    }
                    var isDir = false
                    var size = 0L
                    var mtime = 0L
                    try {
                        isDir = f.isDirectory
                        if (!isDir) size = f.length()
                        mtime = f.lastModified()
                    } catch (e: Throwable) {
                    }
                    out.add(mapOf("name" to name, "dir" to isDir, "size" to size, "mtime" to mtime))
                }
                return out
            }
            "mkdir" -> {
                val f = file(call, path, true)
                if (!f.exists()) f.mkdirs()
                return true
            }
            "rename" -> {
                val to = call.argument<String>("to") ?: ""
                var src = file(call, path, false)
                val isDir = src.isDirectory
                if (isDir) src = file(call, path, true)
                src.renameTo(file(call, to, isDir))
                return true
            }
            "delete" -> {
                var f = file(call, path, false)
                if (!f.exists()) return true
                if (f.isDirectory) f = file(call, path, true)
                f.delete()
                return true
            }
            "size" -> {
                val f = file(call, path, false)
                return if (f.exists()) f.length() else -1L
            }
            "open" -> {
                val write = call.argument<Boolean>("write") ?: false
                val append = call.argument<Boolean>("append") ?: false
                val offset = (call.argument<Number>("offset") ?: 0).toLong()
                val f = file(call, path, false)
                if (write && !append && f.exists()) f.delete()
                val raf = SmbRandomAccessFile(f, if (write) "rw" else "r")
                if (write && append) {
                    raf.seek(raf.length())
                } else if (offset > 0) {
                    raf.seek(offset)
                }
                val id = nextId.getAndIncrement()
                handles[id] = raf
                return id
            }
            "read" -> {
                val id = call.argument<Int>("id") ?: 0
                val n = call.argument<Int>("n") ?: 262144
                val raf = handles[id] ?: throw IllegalStateException("файл закрыт")
                val buf = ByteArray(n)
                var got = 0
                while (got < n) {
                    val r = raf.read(buf, got, n - got)
                    if (r <= 0) break
                    got += r
                }
                return if (got == n) buf else buf.copyOf(got)
            }
            "write" -> {
                val id = call.argument<Int>("id") ?: 0
                val data = call.argument<ByteArray>("data") ?: ByteArray(0)
                val raf = handles[id] ?: throw IllegalStateException("файл закрыт")
                raf.write(data, 0, data.size)
                return true
            }
            "close" -> {
                val id = call.argument<Int>("id") ?: 0
                val raf = handles.remove(id)
                try {
                    raf?.close()
                } catch (e: Throwable) {
                }
                return true
            }
            "reset" -> {
                dropContext(call)
                return true
            }
        }
        throw IllegalArgumentException("unknown method " + call.method)
    }
}
