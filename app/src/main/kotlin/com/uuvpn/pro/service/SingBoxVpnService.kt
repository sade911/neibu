package com.uuvpn.pro.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
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
 * 当 libbox 不可用时，VPN 接口已建立但无实际代理（占位）
 *
 * 集成 libbox 后替换 TODO 部分：
 *   1. 将 libbox.aar 放入 app/libs/
 *   2. 取消注释 LibBox.start() / LibBox.stop() 调用
 *   3. 实现 TrafficMonitor 对接
 */
class SingBoxVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config != null) {
                    startVpn(config)
                }
            }
            ACTION_STOP -> {
                stopVpn()
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

            // 2. 建立 TUN 接口
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
                isRunning = true
                currentStatus = "running"

                // TODO: 集成 libbox 后，在这里调用:
                // val box = Libbox.newService(configFile.absolutePath)
                // box.start()
                //
                // 或使用 fd 方式:
                // Libbox.startWithFd(configFile.absolutePath, vpnInterface!!.fd)

                startForeground(NOTIFICATION_ID, createNotification("已连接"))
                Log.i(TAG, "VPN started with TUN interface fd=${vpnInterface!!.fd}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN: ${e.message}", e)
            currentStatus = "error"
        }
    }

    private fun stopVpn() {
        isRunning = false
        currentStatus = "stopped"

        // TODO: 集成 libbox 后，在这里调用:
        // box?.stop()

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
        stopVpn()
        super.onRevoke()
    }

    // ============================================================
    // 通知
    // ============================================================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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
    // 静态方法 — 供 VpnManager 查询
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
            // TODO: 集成 libbox 后，从 sing-box 获取真实流量统计
            // return mapOf(
            //     "upload" to Libbox.getUploadBytes(),
            //     "download" to Libbox.getDownloadBytes(),
            // )
            return mapOf("upload" to 0L, "download" to 0L)
        }
    }
}
