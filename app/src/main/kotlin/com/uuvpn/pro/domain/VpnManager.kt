package com.uuvpn.pro.domain

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
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
 *
 * 暴露 StateFlow 给 ViewModel 使用
 */
@Singleton
class VpnManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val prefs: PrefsManager,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // ===== State =====
    private val _vpnState = MutableStateFlow(VpnState.DISCONNECTED)
    val vpnState: StateFlow<VpnState> = _vpnState.asStateFlow()

    private val _trafficStats = MutableStateFlow(TrafficStats())
    val trafficStats: StateFlow<TrafficStats> = _trafficStats.asStateFlow()

    private val _connectionStartTime = MutableStateFlow(0L)
    val connectionDuration: StateFlow<Long>
        get() = _connectionStartTime.map { start ->
            if (start > 0) (System.currentTimeMillis() - start) / 1000 else 0L
        }.stateIn(scope, SharingStarted.WhileSubscribed(), 0L)

    private var statsJob: Job? = null

    /**
     * 检查是否需要 VPN 权限
     * @return null 如果已有权限，否则返回需要启动的 Intent
     */
    fun prepareVpn(activity: Activity): Intent? {
        return VpnService.prepare(activity)
    }

    /**
     * 连接 VPN
     */
    suspend fun connect(node: NodeModel, uuid: String) {
        if (_vpnState.value == VpnState.CONNECTING || _vpnState.value == VpnState.CONNECTED) return

        _vpnState.value = VpnState.CONNECTING

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

            // 等待状态变化
            delay(500)
            _vpnState.value = VpnState.CONNECTED
            _connectionStartTime.value = System.currentTimeMillis()
            startStatsTimer()
        } catch (e: Exception) {
            _vpnState.value = VpnState.DISCONNECTED
        }
    }

    /**
     * 断开 VPN
     */
    fun disconnect() {
        if (_vpnState.value == VpnState.DISCONNECTED) return

        _vpnState.value = VpnState.DISCONNECTING

        val intent = Intent(context, SingBoxVpnService::class.java).apply {
            action = SingBoxVpnService.ACTION_STOP
        }
        context.startService(intent)

        _vpnState.value = VpnState.DISCONNECTED
        _connectionStartTime.value = 0L
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
            }
        }
    }

    private fun stopStatsTimer() {
        statsJob?.cancel()
        statsJob = null
    }
}
