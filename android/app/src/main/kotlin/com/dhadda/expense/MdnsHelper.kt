package com.dhadda.expense

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Minimal mDNS advertiser for the phone-hosted tracker.
 *
 * Publishes `name.local` (plus a DNS-SD _http._tcp record) for the
 * already-running local HTTP server while "Show on PC" is active.
 * Best-effort only: every failure path replies ok=false, never throws,
 * so mDNS can never break the existing IP-based access.
 */
class MdnsHelper(private val context: Context) {

    private var listener: NsdManager.RegistrationListener? = null
    private var lock: WifiManager.MulticastLock? = null
    private val main = Handler(Looper.getMainLooper())

    fun register(
        result: MethodChannel.Result,
        name: String,
        type: String,
        port: Int,
    ) {
        unregisterInternal()
        val replied = AtomicBoolean(false)
        fun reply(payload: Map<String, Any?>) {
            if (replied.compareAndSet(false, true)) {
                try {
                    result.success(payload)
                } catch (_: Exception) {
                }
            }
        }
        try {
            val app = context.applicationContext
            val manager =
                app.getSystemService(Context.NSD_SERVICE) as NsdManager
            val wifi =
                app.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mcLock = wifi.createMulticastLock("expense-mdns")
            try {
                mcLock.setReferenceCounted(true)
                mcLock.acquire()
            } catch (_: Exception) {
            }
            lock = mcLock
            val safeType = if (type.endsWith(".")) type else "$type."
            val info = NsdServiceInfo().apply {
                serviceName = name
                serviceType = safeType
                setPort(port)
            }
            val cb = object : NsdManager.RegistrationListener {
                override fun onServiceRegistered(
                    service: NsdServiceInfo,
                ) {
                    reply(
                        mapOf(
                            "ok" to true,
                            "name" to service.serviceName,
                        ),
                    )
                }

                override fun onRegistrationFailed(
                    service: NsdServiceInfo,
                    errorCode: Int,
                ) {
                    Log.w("ExpenseMdns", "register failed: $errorCode")
                    cleanup()
                    reply(
                        mapOf(
                            "ok" to false,
                            "error" to "code $errorCode",
                        ),
                    )
                }

                override fun onServiceUnregistered(
                    service: NsdServiceInfo,
                ) {
                }

                override fun onUnregistrationFailed(
                    service: NsdServiceInfo,
                    errorCode: Int,
                ) {
                }
            }
            listener = cb
            manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, cb)
            main.postDelayed({
                reply(mapOf("ok" to false, "error" to "timeout"))
            }, 10000)
        } catch (e: Exception) {
            Log.w("ExpenseMdns", "register error: $e")
            cleanup()
            reply(mapOf("ok" to false, "error" to "$e"))
        }
    }

    fun unregister() {
        unregisterInternal()
    }

    private fun unregisterInternal() {
        try {
            val manager = context.applicationContext
                .getSystemService(Context.NSD_SERVICE) as NsdManager
            listener?.let { manager.unregisterService(it) }
        } catch (_: Exception) {
        }
        listener = null
        try {
            if (lock?.isHeld == true) lock?.release()
        } catch (_: Exception) {
        }
        lock = null
    }

    private fun cleanup() {
        try {
            if (lock?.isHeld == true) lock?.release()
        } catch (_: Exception) {
        }
        lock = null
        listener = null
    }
}