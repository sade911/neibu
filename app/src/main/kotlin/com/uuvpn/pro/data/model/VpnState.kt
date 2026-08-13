package com.uuvpn.pro.data.model

/**
 * VPN 连接状态
 */
enum class VpnState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    DISCONNECTING;

    val isConnected: Boolean get() = this == CONNECTED
    val isDisconnected: Boolean get() = this == DISCONNECTED
    val isTransitioning: Boolean get() = this == CONNECTING || this == DISCONNECTING
}

/**
 * 实时流量统计
 */
data class TrafficStats(
    val uploadBytes: Long = 0L,
    val downloadBytes: Long = 0L,
) {
    val uploadFormatted: String get() = formatBytes(uploadBytes)
    val downloadFormatted: String get() = formatBytes(downloadBytes)
}

private fun formatBytes(bytes: Long): String {
    if (bytes < 1024) return "${bytes}B"
    if (bytes < 1024 * 1024) return "%.1fKB".format(bytes / 1024.0)
    if (bytes < 1024 * 1024 * 1024) return "%.1fMB".format(bytes / (1024.0 * 1024))
    return "%.2fGB".format(bytes / (1024.0 * 1024 * 1024))
}
