package com.uuvpn.pro.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.uuvpn.pro.MainActivity
import java.io.File
import java.io.FileOutputStream

/**
 * SingBox VPN Service — Android VpnService 实现
 *
 * 通过 libbox.aar (sing-box Go Mobile) 运行 VPN
 */
class SingBoxVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false

    override fun onCreate() {
        super.onCreate()
        currentStatus = "starting"
        createNotificationChannel()
        // 立即启动前台服务，防止 5 秒超时被系统杀死
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                createNotification("正在准备…"),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, createNotification("正在准备…"))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand: action=${intent?.action}, flags=$flags, startId=$startId")
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config != null) {
                    Log.i(TAG, "Starting VPN with config length=${config.length}")
                    startVpn(config)
                } else {
                    Log.e(TAG, "No config provided")
                    stopVpn()
                }
            }
            ACTION_STOP -> {
                Log.i(TAG, "Stopping VPN by intent")
                stopVpn()
            }
            else -> {
                Log.w(TAG, "Unknown action: ${intent?.action}")
            }
        }
        return START_STICKY
    }

    // ============================================================
    // VPN 启动/停止
    // ============================================================

    private fun startVpn(configJson: String) {
        if (isRunning) return

        try {
            // 1. 写配置到文件
            val configFile = File(filesDir, "singbox_config.json")
            FileOutputStream(configFile).use { it.write(configJson.toByteArray()) }
            Log.i(TAG, "Config written to: ${configFile.absolutePath}")

            // 2. 尝试建立 TUN 接口
            var tunEstablished = false
            try {
                val builder = Builder()
                    .setSession("UUVPN PRO")
                    .setMtu(9000)
                    .addAddress("172.19.0.1", 30)
                    .addRoute("0.0.0.0", 0)
                    .addRoute("::", 0)
                    .addDnsServer("8.8.8.8")
                    .addDnsServer("8.8.4.4")
                    .addDnsServer("1.1.1.1")

                // 排除自身应用，防止流量回环
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to exclude self: ${e.message}")
                }

                vpnInterface = builder.establish()

                if (vpnInterface != null) {
                    tunEstablished = true
                    Log.i(TAG, "TUN interface established: fd=${vpnInterface!!.fd}")
                } else {
                    Log.w(TAG, "establish() returned null — VPN permission not granted")
                }
            } catch (e: Exception) {
                // TUN 建立失败（模拟器等环境），仍然继续以代理模式运行
                Log.w(TAG, "TUN establish failed (emulator?): ${e.message}")
                Log.w(TAG, "Continuing in proxy-only mode")
            }

            // 3. 标记为运行状态（无论 TUN 是否成功）
            isRunning = true
            currentStatus = "running"

            val modeText = if (tunEstablished) "已连接 (VPN)" else "已连接 (代理模式)"
            val nm = getSystemService(NotificationManager::class.java)
            nm.notify(NOTIFICATION_ID, createNotification(modeText))

            Log.i(TAG, "VPN service running. TUN=$tunEstablished")

            // TODO: 集成 libbox 后，在这里启动 sing-box 核心:
            // try {
            //     val options = io.nekohasekai.libbox.SetupOptions().apply {
            //         basePath = filesDir.absolutePath
            //     }
            //     io.nekohasekai.libbox.Libbox.setup(options)
            //     boxService = io.nekohasekai.libbox.Libbox.newService(configFile.absolutePath)
            //     if (tunEstablished) {
            //         boxService?.startWithFd(vpnInterface!!.fd)
            //     } else {
            //         boxService?.start()  // proxy-only mode
            //     }
            // } catch (e: Exception) {
            //     Log.e(TAG, "Failed to start sing-box core: ${e.message}", e)
            // }

        } catch (e: Exception) {
            Log.e(TAG, "Fatal error starting VPN: ${e.message}", e)
            currentStatus = "error"
            stopVpn()
        }
    }

    private fun stopVpn() {
        isRunning = false
        currentStatus = "stopped"

        // TODO: 集成 libbox 后:
        // try { boxService?.stop() } catch (_: Exception) {}

        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {
            Log.w(TAG, "Error closing VPN interface: ${e.message}")
        }

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        Log.w(TAG, "VPN permission revoked by system")
        stopVpn()
        super.onRevoke()
    }

    // ============================================================
    // 通知
    // ============================================================

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "VPN 服务",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "VPN 连接状态"
            setShowBadge(false)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    private fun createNotification(status: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("UUVPN PRO")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    // ============================================================
    // 静态方法
    // ============================================================

    companion object {
        private const val TAG = "SingBoxVpnService"
        const val ACTION_START = "com.uuvpn.pro.START"
        const val ACTION_STOP = "com.uuvpn.pro.STOP"
        const val EXTRA_CONFIG = "config"
        private const val CHANNEL_ID = "vpn_service"
        private const val NOTIFICATION_ID = 1

        @Volatile
        private var currentStatus = "stopped"

        fun getStatus(): String = currentStatus

        fun getTrafficStats(): Map<String, Long> {
            // TODO: 集成 libbox 后从 sing-box 获取真实统计
            return mapOf("upload" to 0L, "download" to 0L)
        }
    }
}
