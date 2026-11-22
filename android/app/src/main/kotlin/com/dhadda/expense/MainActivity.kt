package com.dhadda.expense

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import org.json.JSONObject
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val mdns by lazy { MdnsHelper(this) }
    private val sms by lazy { SmsBridge(this) }
    private val media by lazy { MediaBridge(this) }
    private var permResult: MethodChannel.Result? = null

    companion object {
        const val PERM_CODE = 0x5E56
        const val PERM_NOTIF_CODE = 0x5E57
        /** Set by a widget tap, consumed by Dart on the next unlock/frame. */
        var pendingQuickAction: String? = null
        var actionChannel: MethodChannel? = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(QUICK_ACTION_EXTRA)?.let { action ->
            pendingQuickAction = action
            actionChannel?.invokeMethod("action", action, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        intent.getStringExtra(QUICK_ACTION_EXTRA)?.let {
            pendingQuickAction = it
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "expense/widget",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> {
                    val payload = call.arguments
                    if (payload is Map<*, *>) {
                        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                            .edit()
                            .putString(
                                "flutter.widget_calendar_snapshot_v1",
                                JSONObject(payload).toString(),
                            )
                            .apply()
                    }
                    refreshWidgets(this)
                    result.success(null)
                }
                "takeQuickAction" -> {
                    result.success(pendingQuickAction)
                    pendingQuickAction = null
                }
                else -> result.notImplemented()
            }
        }
        actionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "expense/widget_actions",
        )
        val hostChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "expense/host_service",
        )
        DhaddaHostService.channel = hostChannel
        hostChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startService(Intent(this, DhaddaHostService::class.java))
                    result.success(true)
                }
                "stop" -> {
                    stopService(Intent(this, DhaddaHostService::class.java))
                    result.success(true)
                }
                "updateConnected" -> {
                    if (call.argument<Boolean>("connected") == true) {
                        DhaddaHostService.lastConnected = System.currentTimeMillis()
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "expense/mdns",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "register" -> mdns.register(
                    result,
                    call.argument<String>("name") ?: "dhadda",
                    call.argument<String>("type") ?: "_http._tcp.",
                    call.argument<Int>("port") ?: 8080,
                )
                "unregister" -> {
                    mdns.unregister()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "expense/sms",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensurePermission" -> sms.ensurePermission(result)
                "readInbox" -> try {
                    result.success(
                        sms.readInbox(
                            (call.argument<Int>("limit") ?: 100),
                        ),
                    )
                } catch (e: Exception) {
                    result.error("SMS", "$e", null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "expense/media",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePhoto" -> media.takePhoto(result)
                "pickImages" -> media.pickImages(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "expense/perm",
        ).setMethodCallHandler { call, result ->
            if (call.method == "ensure") {
                val name = call.argument<String>("name")
                val notification = name == Manifest.permission.POST_NOTIFICATIONS
                if (name != Manifest.permission.CAMERA && !notification) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                if (ContextCompat.checkSelfPermission(this, name!!) ==
                    PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(true)
                } else {
                    permResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(name),
                        if (notification) PERM_NOTIF_CODE else PERM_CODE,
                    )
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (media.onResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (sms.onRequestPermissionsResult(
                requestCode, permissions, grantResults,
            )
        ) {
            return
        }
        if (requestCode == PERM_CODE || requestCode == PERM_NOTIF_CODE) {
            val ok = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            permResult?.success(ok)
            permResult = null
            return
        }
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults,
        )
    }
}
