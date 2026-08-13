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
import io.nekohasekai.libbox.*
import java.io.File
import java.io.FileOutputStream

/**
 * SingBox VPN Service — 通过 libbox.aar 运行 sing-box 核心
 */
class SingBoxVpnService : VpnService(), CommandServerHandler {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    private var commandServer: CommandServer? = null

    override fun onCreate() {
        super.onCreate()
        currentStatus = "starting"
        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                createNotification("正在准备…"),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, createNotification("正在准备…"))
        }

        // 初始化 libbox
        try {
            val options = SetupOptions().apply {
                basePath = filesDir.absolutePath
                workingPath = "${filesDir.absolutePath}/work"
                tempPath = "${cacheDir.absolutePath}/temp"
            }
            File(options.workingPath).mkdirs()
            File(options.tempPath).mkdirs()
            Libbox.setup(options)
            Log.i(TAG, "Libbox setup OK, version: ${Libbox.goVersion()}")
        } catch (e: Exception) {
            Log.e(TAG, "Libbox setup failed: ${e.message}", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand: action=${intent?.action}")
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config != null) {
                    startVpn(config)
                } else {
                    Log.e(TAG, "No config provided")
                    stopVpn()
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
            Log.i(TAG, "Config written: ${configFile.absolutePath} (${configJson.length} bytes)")

            // 2. 创建 PlatformInterface
            val platformInterface = BoxPlatformInterface(this)

            // 3. 创建并启动 CommandServer
            commandServer = Libbox.newCommandServer(this as CommandServerHandler, platformInterface)
            commandServer?.start()
            Log.i(TAG, "CommandServer started")

            // 4. 启动 sing-box service
            commandServer?.startOrReloadService(configJson, OverrideOptions())
            Log.i(TAG, "sing-box service started")

            isRunning = true
            currentStatus = "running"

            val nm = getSystemService(NotificationManager::class.java)
            nm.notify(NOTIFICATION_ID, createNotification("已连接"))

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN: ${e.message}", e)
            currentStatus = "error"
            stopVpn()
        }
    }

    private fun stopVpn() {
        isRunning = false
        currentStatus = "stopped"

        try {
            commandServer?.closeService()
            Log.i(TAG, "sing-box service closed")
        } catch (e: Exception) {
            Log.w(TAG, "Error closing sing-box: ${e.message}")
        }

        try {
            commandServer?.close()
            commandServer = null
        } catch (e: Exception) {
            Log.w(TAG, "Error closing CommandServer: ${e.message}")
        }

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
        Log.w(TAG, "VPN permission revoked")
        stopVpn()
        super.onRevoke()
    }

    // ============================================================
    // CommandServerHandler 实现
    // ============================================================

    override fun serviceReload() {
        Log.i(TAG, "serviceReload requested")
    }

    override fun serviceStop() {
        Log.i(TAG, "serviceStop requested")
        stopVpn()
    }

    override fun getSystemProxyStatus(): SystemProxyStatus? = null

    override fun setSystemProxyEnabled(enabled: Boolean) {}

    override fun connectSSHAgent(): Int = -1

    override fun triggerNativeCrash() {}

    override fun writeDebugMessage(message: String) {
        Log.d(TAG, "Debug: $message")
    }

    // ============================================================
    // PlatformInterface 实现 — sing-box 通过回调来建立 TUN
    // ============================================================

    inner class BoxPlatformInterface(private val service: SingBoxVpnService) : PlatformInterface {

        override fun openTun(options: TunOptions): Int {
            Log.i(TAG, "openTun called, MTU=${options.mtu}")

            val builder = Builder()
                .setSession("UUVPN PRO")
                .setMtu(options.mtu)

            // 添加地址
            val inet4Iter = options.inet4Address
            while (inet4Iter.hasNext()) {
                val prefix = inet4Iter.next()
                builder.addAddress(prefix.address(), prefix.prefix())
            }

            val inet6Iter = options.inet6Address
            while (inet6Iter.hasNext()) {
                val prefix = inet6Iter.next()
                builder.addAddress(prefix.address(), prefix.prefix())
            }

            // 添加路由
            if (options.autoRoute) {
                val inet4RouteIter = options.inet4RouteAddress
                while (inet4RouteIter.hasNext()) {
                    val prefix = inet4RouteIter.next()
                    builder.addRoute(prefix.address(), prefix.prefix())
                }
                val inet6RouteIter = options.inet6RouteAddress
                while (inet6RouteIter.hasNext()) {
                    val prefix = inet6RouteIter.next()
                    builder.addRoute(prefix.address(), prefix.prefix())
                }
            }

            // DNS
            val dnsIter = options.getDNSServerAddress()
            while (dnsIter.hasNext()) {
                builder.addDnsServer(dnsIter.next())
            }

            // 排除自身应用
            try {
                builder.addDisallowedApplication(service.packageName)
            } catch (_: Exception) {}

            // 排除指定应用
            val excludeIter = options.excludePackage
            while (excludeIter.hasNext()) {
                try {
                    builder.addDisallowedApplication(excludeIter.next())
                } catch (_: Exception) {}
            }

            service.vpnInterface?.close()
            service.vpnInterface = builder.establish()

            return if (service.vpnInterface != null) {
                val fd = service.vpnInterface!!.fd
                Log.i(TAG, "TUN established, fd=$fd")
                // protect 保护自身 socket 不走 VPN
                fd
            } else {
                Log.e(TAG, "TUN establish() returned null")
                -1
            }
        }

        override fun autoDetectInterfaceControl(fd: Int) {
            // 保护 socket 不走 VPN（防止回环）
            service.protect(fd)
        }

        override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
        override fun usePlatformBridge(): Boolean = false
        override fun useProcFS(): Boolean = false
        override fun usePlatformShell(): Boolean = false
        override fun includeAllNetworks(): Boolean = false
        override fun underNetworkExtension(): Boolean = false

        override fun findConnectionOwner(ipProtocol: Int, sourceAddress: String?, sourcePort: Int, destinationAddress: String?, destinationPort: Int): ConnectionOwner? = null
        override fun getInterfaces(): NetworkInterfaceIterator? = null
        override fun localDNSTransport(): LocalDNSTransport? = null
        override fun readWIFIState(): WIFIState? = null
        override fun clearDNSCache() {}
        override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {}
        override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) {}
        override fun startNeighborMonitor(listener: NeighborUpdateListener?) {}
        override fun closeNeighborMonitor(listener: NeighborUpdateListener?) {}
        override fun sendNotification(notification: io.nekohasekai.libbox.Notification?) {}
        override fun registerMyInterface(interfaceName: String?) {}
        override fun tailscaleHostname(): String = ""
        override fun readSystemSSHHostKey(): String = ""
        override fun lookupSFTPServer(): String = ""
        override fun lookupUser(name: String?): PlatformUser? = null
        override fun openShellSession(user: PlatformUser?, command: String?, args: StringIterator?, term: String?, height: Int, width: Int): ShellSession? = null
        override fun checkPlatformShell() {}
        override fun createBridge(options: BridgeOptions?): BridgeSession? = null
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
            // TODO: 通过 CommandClient 获取真实流量
            return mapOf("upload" to 0L, "download" to 0L)
        }
    }
}
