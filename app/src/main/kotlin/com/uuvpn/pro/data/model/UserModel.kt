package com.uuvpn.pro.data.model

/**
 * 用户模型
 */
data class UserModel(
    val id: Int,
    val email: String,
    val planId: Int? = null,
    val expiredAt: Long? = null,        // Unix 秒
    val transferEnable: Long = 0,       // 总流量 bytes
    val transferUsed: Long = 0,         // 已用流量 bytes
    val token: String? = null,
) {
    val usedGB: Double get() = transferUsed / (1024.0 * 1024 * 1024)
    val totalGB: Double get() = transferEnable / (1024.0 * 1024 * 1024)
    val usagePercent: Float
        get() = if (transferEnable > 0) (transferUsed.toFloat() / transferEnable) else 0f

    val isExpired: Boolean
        get() = expiredAt != null && System.currentTimeMillis() / 1000 > expiredAt

    val expiredDateStr: String
        get() {
            if (expiredAt == null) return "永久"
            val dt = java.util.Date(expiredAt * 1000)
            val fmt = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
            return fmt.format(dt)
        }
}
