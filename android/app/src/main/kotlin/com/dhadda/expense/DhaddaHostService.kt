package com.dhadda.expense

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

/**
 * Keeps the Dart isolate (and its HttpServer) alive while "Use on computer"
 * is on. The HTTP server itself still runs in Dart; this service only holds
 * a foreground notification, a partial wake lock and a Wi-Fi lock, and
 * auto-stops after two hours with no connected computer.
 */
class DhaddaHostService : Service() {
    companion object {
        const val ACTION_STOP = "com.dhadda.expense.STOP_HOST"
        const val CHANNEL_ID = "dhadda_host"
        const val NOTIFICATION_ID = 4101
        const val IDLE_MS = 2 * 60 * 60 * 1000L
        @Volatile
        var channel: MethodChannel? = null
        @Volatile
        var lastConnected: Long = System.currentTimeMillis()
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val stopReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            requestDartStop()
            stopSelf()
        }
    }
    private val idleCheck = object : Runnable {
        override fun run() {
            if (System.currentTimeMillis() - lastConnected > IDLE_MS) {
                requestDartStop()
                stopSelf()
                return
            }
            handler.postDelayed(this, 60_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        ContextCompat.registerReceiver(
            this,
            stopReceiver,
            IntentFilter(ACTION_STOP),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        startForeground(NOTIFICATION_ID, notification())
        acquireLocks()
        handler.post(idleCheck)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            requestDartStop()
            stopSelf()
            return START_NOT_STICKY
        }
        lastConnected = System.currentTimeMillis()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun requestDartStop() {
        channel?.invokeMethod("stopRequested", null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(code: String, message: String?, details: Any?) {}
                override fun notImplemented() {}
            })
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager?.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Use on computer",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "Dhadda is sharing your expenses with a computer"
        manager?.createNotificationChannel(channel)
    }

    private fun notification(): android.app.Notification {
        val intent = Intent(ACTION_STOP, null, this, DhaddaHostService::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val stop = PendingIntent.getBroadcast(this, 0, intent, flags)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Dhadda is available on your computer")
            .setContentText("Tap Stop when you are done")
            .setOngoing(true)
            .addAction(android.R.drawable.ic_delete, "Stop", stop)
            .build()
    }

    private fun acquireLocks() {
        try {
            val pm = getSystemService(PowerManager::class.java)
            wakeLock = pm?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK, "Dhadda::Host",
            )?.apply { acquire(IDLE_MS + 60_000) }
        } catch (_: Exception) {
        }
        try {
            val wm = applicationContext.getSystemService(WIFI_SERVICE) as? WifiManager
            @Suppress("DEPRECATION")
            wifiLock = wm?.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Dhadda::Host",
            )?.apply { acquire() }
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(idleCheck)
        try { unregisterReceiver(stopReceiver) } catch (_: Exception) {}
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        try { if (wifiLock?.isHeld == true) wifiLock?.release() } catch (_: Exception) {}
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
