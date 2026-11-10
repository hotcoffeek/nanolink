package com.nanolink.nanolink

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Кнопки «Принять / Отклонить» в уведомлении: работают при выключенном экране. */
class RecvActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val ok = intent.action == "nanolink.RECV_YES"
        val id = intent.getIntExtra("id", 2)
        try {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(id)
        } catch (_: Exception) {
        }
        try {
            MainActivity.chanRef?.invokeMethod("recvAnswer", mapOf("ok" to ok))
        } catch (_: Exception) {
        }
    }
}
