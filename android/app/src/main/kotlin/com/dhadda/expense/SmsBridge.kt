package com.dhadda.expense

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Reads transaction SMS from the inbox for optional expense import.
 * Opt-in only: nothing is read until the user taps "Import from SMS".
 * Best-effort: permission denial or provider errors yield empty results.
 */
class SmsBridge(private val activity: Activity) :
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val REQUEST_CODE = 0x5E55
        const val MAX_ROWS = 300
    }

    private var pending: MethodChannel.Result? = null

    fun ensurePermission(result: MethodChannel.Result) {
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.READ_SMS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        pending = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.READ_SMS),
            REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val ok = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending?.success(ok)
        pending = null
        return true
    }

    fun readInbox(limit: Int): List<Map<String, Any?>> {
        if (ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.READ_SMS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("sms permission denied")
        }
        val out = mutableListOf<Map<String, Any?>>()
        val since = System.currentTimeMillis() - 90L * 24 * 3600 * 1000
        val cursor = activity.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
            ),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} DESC",
        ) ?: return out
        cursor.use {
            val iId = it.getColumnIndexOrThrow(Telephony.Sms._ID)
            val iAddr = it.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val iBody = it.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val iDate = it.getColumnIndexOrThrow(Telephony.Sms.DATE)
            var n = 0
            val cap = limit.coerceIn(1, MAX_ROWS)
            while (it.moveToNext() && n < cap) {
                n++
                out.add(
                    mapOf(
                        "id" to it.getString(iId),
                        "sender" to (it.getString(iAddr) ?: ""),
                        "body" to (it.getString(iBody) ?: ""),
                        "date" to it.getLong(iDate),
                    ),
                )
            }
        }
        return out
    }
}