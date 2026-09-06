package com.dhadda.expense

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val mdns by lazy { MdnsHelper(this) }
    private val sms by lazy { SmsBridge(this) }
    private var permResult: MethodChannel.Result? = null

    companion object {
        const val PERM_CODE = 0x5E56
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
            "expense/perm",
        ).setMethodCallHandler { call, result ->
            if (call.method == "ensure") {
                // Only the camera permission is ever granted here.
                if (call.argument<String>("name") !=
                    Manifest.permission.CAMERA
                ) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.CAMERA,
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(true)
                } else {
                    permResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.CAMERA),
                        PERM_CODE,
                    )
                }
            } else {
                result.notImplemented()
            }
        }
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
        if (requestCode == PERM_CODE) {
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
