package com.nanolink.nanolink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Держит процесс живым в фоне и привязывает сокеты процесса к Wi-Fi/Ethernet,
 * чтобы VPN не уводил трафик к устройствам локальной сети в туннель.
 */
class KeepAliveService : Service() {
    private var wifiLock: WifiManager.WifiLock? = null
    private var wifiLock2: WifiManager.WifiLock? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val bind = intent?.getBooleanExtra("bind", true) ?: true
        startAsForeground()
        acquireLocks()
        if (bind) bindToLan() else unbind()
        return START_STICKY
    }

    private fun startAsForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("nanolink", "NanoLink", NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, "nanolink")
        else @Suppress("DEPRECATION") Notification.Builder(this)
        val n = b.setContentTitle("NanoLink")
            .setContentText("Держим связь с вашими устройствами")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(1, n)
        }
    }

    private fun acquireLocks() {
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (wifiLock == null) {
                @Suppress("DEPRECATION")
                val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
                wifiLock = wm.createWifiLock(mode, "nanolink:wifi").apply { setReferenceCounted(false); acquire() }
            }
            if (wifiLock2 == null && Build.VERSION.SDK_INT >= 29) {
                // Низкая задержка действует только при включённом экране; второй замок держит Wi-Fi
                // «полной мощности» и при выключенном экране (на старых версиях Android так работает всегда).
                @Suppress("DEPRECATION")
                wifiLock2 = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "nanolink:wifi2").apply { setReferenceCounted(false); acquire() }
            }
            if (multicastLock == null) {
                multicastLock = wm.createMulticastLock("nanolink:multicast").apply { setReferenceCounted(false); acquire() }
            }
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nanolink:cpu").apply { setReferenceCounted(false); acquire() }
            }
        } catch (_: Exception) {
        }
    }

    private fun bindToLan() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            if (callback != null) return
            val req = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .addTransportType(NetworkCapabilities.TRANSPORT_ETHERNET)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build()
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    cm.bindProcessToNetwork(network)
                }

                override fun onLost(network: Network) {
                    // Сеть пропала: снимаем привязку, при возвращении onAvailable привяжет заново.
                    cm.bindProcessToNetwork(null)
                }
            }
            callback = cb
            cm.requestNetwork(req, cb)
        } catch (_: Exception) {
        }
    }

    private fun unbind() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            callback?.let { cm.unregisterNetworkCallback(it) }
            callback = null
            cm.bindProcessToNetwork(null)
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        unbind()
        try { wifiLock?.takeIf { it.isHeld }?.release() } catch (_: Exception) {}
        try { wifiLock2?.takeIf { it.isHeld }?.release() } catch (_: Exception) {}
        try { multicastLock?.takeIf { it.isHeld }?.release() } catch (_: Exception) {}
        try { wakeLock?.takeIf { it.isHeld }?.release() } catch (_: Exception) {}
        wifiLock = null; wifiLock2 = null; multicastLock = null; wakeLock = null
        super.onDestroy()
    }
}
