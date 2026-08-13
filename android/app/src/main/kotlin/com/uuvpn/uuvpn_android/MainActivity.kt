package com.uuvpn.uuvpn_android

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.uuvpn/singbox"
    private var pendingConfig: String? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val config = call.argument<String>("config")
                    if (config != null) {
                        startVpn(config)
                        result.success(true)
                    } else {
                        result.error("NO_CONFIG", "Config is null", null)
                    }
                }
                "stop" -> {
                    stopVpn()
                    result.success(true)
                }
                "getStatus" -> {
                    result.success(SingBoxVpnService.getStatus())
                }
                "getTrafficStats" -> {
                    result.success(SingBoxVpnService.getTrafficStats())
                }
                "requestVpnPermission" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, VPN_PERMISSION_REQUEST)
                        result.success(false)
                    } else {
                        result.success(true) // Already granted
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startVpn(config: String) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingConfig = config
            startActivityForResult(intent, VPN_PERMISSION_REQUEST)
        } else {
            launchVpnService(config)
        }
    }

    private fun stopVpn() {
        val intent = Intent(this, SingBoxVpnService::class.java)
        intent.action = SingBoxVpnService.ACTION_STOP
        startService(intent)
    }

    private fun launchVpnService(config: String) {
        val intent = Intent(this, SingBoxVpnService::class.java)
        intent.action = SingBoxVpnService.ACTION_START
        intent.putExtra(SingBoxVpnService.EXTRA_CONFIG, config)
        startForegroundService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST && resultCode == RESULT_OK) {
            pendingConfig?.let { launchVpnService(it) }
            pendingConfig = null
        }
    }

    companion object {
        private const val VPN_PERMISSION_REQUEST = 1001
    }
}
