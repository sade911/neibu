package com.uuvpn.pro.domain

import android.content.Context
import android.content.Intent
import android.util.Log
import com.uuvpn.pro.data.local.PrefsManager
import com.uuvpn.pro.data.model.NodeModel
import com.uuvpn.pro.data.model.TrafficStats
import com.uuvpn.pro.data.model.VpnState
import com.uuvpn.pro.service.SingBoxVpnService
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import javax.inject.Inject
import javax.inject.Singleton

/**
 * VPN 管理器 — 统一管理 VPN 连接生命周期
 */
@Singleton
class VpnManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val prefs: PrefsManager,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    companion object {
        private const val TAG = "VpnManager"
    }

    // ===== State =====
    private val _vpnState = MutableStateFlow(VpnState.DISCONNECTED)
    val vpnState: StateFlow<VpnState> = _vpnState.asStateFlow()

    private val _trafficStats = MutableStateFlow(TrafficStats())
    val trafficStats: StateFlow<TrafficStats> = _trafficStats.asStateFlow()

    private var connectionStartTime = 0L
    private var statsJob: Job? = null

    /**
     * 连接 VPN
     */
    suspend fun connect(node: NodeModel, uuid: String) {
        if (_vpnState.value == VpnState.CONNECTING || _vpnState.value == VpnState.CONNECTED) {
            Log.d(TAG, "Already connecting/connected, ignoring")
            return
        }

        _vpnState.value = VpnState.CONNECTING
        Log.i(TAG, ">>> Connecting to: ${node.name} type=${node.type} host=${node.host}:${node.port}")

        try {
            val routeMode = prefs.routeMode.first()
            val logLevel = prefs.logLevel.first()
            Log.d(TAG, "Route mode: $routeMode, Log level: $logLevel")

            val configJson = ConfigBuilder.build(
                node = node,
                uuid = uuid,
                routeMode = routeMode,
                logLevel = logLevel,
            )
            Log.d(TAG, "Config built OK, length=${configJson.length}")

            // 启动 VPN Service
            val intent = Intent(context, SingBoxVpnService::class.java).apply {
                action = SingBoxVpnService.ACTION_START
                putExtra(SingBoxVpnService.EXTRA_CONFIG, configJson)
            }
            context.startForegroundService(intent)
            Log.d(TAG, "startForegroundService sent")

            // 等待 Service 启动并建立 TUN
            delay(1500)
            val status = SingBoxVpnService.getStatus()
            Log.i(TAG, "Service status after 1.5s: $status")

            if (status == "running") {
                _vpnState.value = VpnState.CONNECTED
                connectionStartTime = System.currentTimeMillis()
                startStatsTimer()
                Log.i(TAG, ">>> CONNECTED <<<")
            } else {
                // 再等一下
                delay(1500)
                val status2 = SingBoxVpnService.getStatus()
                Log.i(TAG, "Service status after 3s: $status2")

                if (status2 == "running") {
                    _vpnState.value = VpnState.CONNECTED
                    connectionStartTime = System.currentTimeMillis()
                    startStatsTimer()
                    Log.i(TAG, ">>> CONNECTED (delayed) <<<")
                } else {
                    Log.e(TAG, ">>> FAILED: Service status is '$status2' <<<")
                    _vpnState.value = VpnState.DISCONNECTED
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, ">>> Connection error: ${e.message}", e)
            _vpnState.value = VpnState.DISCONNECTED
        }
    }

    /**
     * 断开 VPN
     */
    fun disconnect() {
        if (_vpnState.value == VpnState.DISCONNECTED) return

        Log.i(TAG, ">>> Disconnecting")
        _vpnState.value = VpnState.DISCONNECTING

        try {
            val intent = Intent(context, SingBoxVpnService::class.java).apply {
                action = SingBoxVpnService.ACTION_STOP
            }
            context.startService(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to send stop: ${e.message}")
        }

        _vpnState.value = VpnState.DISCONNECTED
        connectionStartTime = 0L
        _trafficStats.value = TrafficStats()
        stopStatsTimer()
    }

    /**
     * 切换连接状态
     */
    suspend fun toggleConnection(node: NodeModel?, uuid: String?) {
        if (_vpnState.value == VpnState.CONNECTED) {
            disconnect()
        } else if (_vpnState.value == VpnState.DISCONNECTED && node != null && uuid != null) {
            connect(node, uuid)
        }
    }

    // ============================================================
    // Traffic Stats Timer
    // ============================================================

    private fun startStatsTimer() {
        statsJob?.cancel()
        statsJob = scope.launch {
            while (isActive) {
                delay(1000)
                val stats = SingBoxVpnService.getTrafficStats()
                _trafficStats.value = TrafficStats(
                    uploadBytes = stats["upload"] ?: 0L,
                    downloadBytes = stats["download"] ?: 0L,
                )

                // 持续监控 Service 状态
                if (SingBoxVpnService.getStatus() != "running" && _vpnState.value == VpnState.CONNECTED) {
                    Log.w(TAG, "Service died, marking disconnected")
                    _vpnState.value = VpnState.DISCONNECTED
                    connectionStartTime = 0L
                    stopStatsTimer()
                }
            }
        }
    }

    private fun stopStatsTimer() {
        statsJob?.cancel()
        statsJob = null
    }
}
