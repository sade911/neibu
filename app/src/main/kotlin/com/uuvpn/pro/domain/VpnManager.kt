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

    private val _connectionStartTime = MutableStateFlow(0L)

    private var statsJob: Job? = null
    private var statusCheckJob: Job? = null

    /**
     * 连接 VPN
     */
    suspend fun connect(node: NodeModel, uuid: String) {
        if (_vpnState.value == VpnState.CONNECTING || _vpnState.value == VpnState.CONNECTED) return

        _vpnState.value = VpnState.CONNECTING
        Log.i(TAG, "Connecting to ${node.name} (${node.type})")

        try {
            val routeMode = prefs.routeMode.first()
            val logLevel = prefs.logLevel.first()

            val configJson = ConfigBuilder.build(
                node = node,
                uuid = uuid,
                routeMode = routeMode,
                logLevel = logLevel,
            )

            val intent = Intent(context, SingBoxVpnService::class.java).apply {
                action = SingBoxVpnService.ACTION_START
                putExtra(SingBoxVpnService.EXTRA_CONFIG, configJson)
            }
            context.startForegroundService(intent)

            // 轮询检查 Service 状态
            startStatusCheck()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to connect: ${e.message}", e)
            _vpnState.value = VpnState.DISCONNECTED
        }
    }

    /**
     * 断开 VPN
     */
    fun disconnect() {
        if (_vpnState.value == VpnState.DISCONNECTED) return

        Log.i(TAG, "Disconnecting")
        _vpnState.value = VpnState.DISCONNECTING

        val intent = Intent(context, SingBoxVpnService::class.java).apply {
            action = SingBoxVpnService.ACTION_STOP
        }
        try {
            context.startService(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to send stop intent: ${e.message}")
        }

        _vpnState.value = VpnState.DISCONNECTED
        _connectionStartTime.value = 0L
        _trafficStats.value = TrafficStats()
        stopStatsTimer()
        stopStatusCheck()
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

    /**
     * 更新状态（由 VPN Service 回调）
     */
    fun updateState(state: VpnState) {
        _vpnState.value = state
        if (state == VpnState.CONNECTED && _connectionStartTime.value == 0L) {
            _connectionStartTime.value = System.currentTimeMillis()
            startStatsTimer()
        } else if (state == VpnState.DISCONNECTED) {
            _connectionStartTime.value = 0L
            _trafficStats.value = TrafficStats()
            stopStatsTimer()
        }
    }

    // ============================================================
    // Status Check — 轮询 Service 状态
    // ============================================================

    private fun startStatusCheck() {
        statusCheckJob?.cancel()
        statusCheckJob = scope.launch {
            var attempts = 0
            while (isActive && attempts < 10) {
                delay(500)
                val status = SingBoxVpnService.getStatus()
                Log.d(TAG, "Service status check #$attempts: $status")

                when (status) {
                    "running" -> {
                        _vpnState.value = VpnState.CONNECTED
                        _connectionStartTime.value = System.currentTimeMillis()
                        startStatsTimer()
                        return@launch
                    }
                    "error", "stopped" -> {
                        if (_vpnState.value == VpnState.CONNECTING) {
                            _vpnState.value = VpnState.DISCONNECTED
                        }
                        return@launch
                    }
                }
                attempts++
            }
            // 超时
            if (_vpnState.value == VpnState.CONNECTING) {
                Log.w(TAG, "Connection timed out")
                _vpnState.value = VpnState.DISCONNECTED
            }
        }
    }

    private fun stopStatusCheck() {
        statusCheckJob?.cancel()
        statusCheckJob = null
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

                // 检查是否断开了
                if (SingBoxVpnService.getStatus() != "running") {
                    _vpnState.value = VpnState.DISCONNECTED
                    _connectionStartTime.value = 0L
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
