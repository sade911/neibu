package com.uuvpn.pro.service

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 流量监控器
 *
 * 用于在 UI 层展示实时流量
 * TODO: 集成 libbox 后从 sing-box 获取真实数据
 */
@Singleton
class TrafficMonitor @Inject constructor() {

    private val _uploadSpeed = MutableStateFlow(0L)     // bytes/s
    val uploadSpeed: StateFlow<Long> = _uploadSpeed.asStateFlow()

    private val _downloadSpeed = MutableStateFlow(0L)   // bytes/s
    val downloadSpeed: StateFlow<Long> = _downloadSpeed.asStateFlow()

    private val _totalUpload = MutableStateFlow(0L)     // bytes
    val totalUpload: StateFlow<Long> = _totalUpload.asStateFlow()

    private val _totalDownload = MutableStateFlow(0L)   // bytes
    val totalDownload: StateFlow<Long> = _totalDownload.asStateFlow()

    private var lastUpload = 0L
    private var lastDownload = 0L
    private var lastTimestamp = 0L

    /**
     * 由定时器每秒调用，更新流量数据
     */
    fun update(uploadBytes: Long, downloadBytes: Long) {
        val now = System.currentTimeMillis()
        val elapsed = if (lastTimestamp > 0) (now - lastTimestamp) / 1000.0 else 1.0

        if (elapsed > 0) {
            _uploadSpeed.value = ((uploadBytes - lastUpload) / elapsed).toLong().coerceAtLeast(0)
            _downloadSpeed.value = ((downloadBytes - lastDownload) / elapsed).toLong().coerceAtLeast(0)
        }

        _totalUpload.value = uploadBytes
        _totalDownload.value = downloadBytes
        lastUpload = uploadBytes
        lastDownload = downloadBytes
        lastTimestamp = now
    }

    fun reset() {
        _uploadSpeed.value = 0L
        _downloadSpeed.value = 0L
        _totalUpload.value = 0L
        _totalDownload.value = 0L
        lastUpload = 0L
        lastDownload = 0L
        lastTimestamp = 0L
    }
}
