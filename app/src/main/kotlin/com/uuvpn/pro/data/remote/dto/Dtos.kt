package com.uuvpn.pro.data.remote.dto

import com.google.gson.annotations.SerializedName

// ============================================================
// 通用 API 响应
// ============================================================
data class ApiResponse<T>(
    val data: T? = null,
    val message: String? = null,
)

// ============================================================
// Auth
// ============================================================
data class LoginRequest(
    val email: String,
    val password: String,
)

data class RegisterRequest(
    val email: String,
    val password: String,
    @SerializedName("invite_code")
    val inviteCode: String? = null,
)

data class LoginData(
    @SerializedName("auth_data")
    val authData: String? = null,
    val token: String? = null,
) {
    /** 兼容不同版本的 Xboard 返回 */
    val authToken: String? get() = authData ?: token
}

// ============================================================
// User
// ============================================================
data class UserInfoData(
    val id: Int = 0,
    val email: String = "",
    @SerializedName("plan_id")
    val planId: Int? = null,
    @SerializedName("expired_at")
    val expiredAt: Long? = null,
    @SerializedName("transfer_enable")
    val transferEnable: Long = 0,
    val d: Long = 0,     // 下行已用
    val u: Long = 0,     // 上行已用
    val token: String? = null,
)

data class SubscribeData(
    @SerializedName("subscribe_url")
    val subscribeUrl: String? = null,
    val plan: PlanData? = null,
)

data class PlanData(
    val id: Int = 0,
    val name: String = "",
    @SerializedName("transfer_enable")
    val transferEnable: Long = 0,
    @SerializedName("month_price")
    val monthPrice: Int? = null,
)

// ============================================================
// Nodes
// ============================================================
data class NodeData(
    val id: Int = 0,
    val name: String = "Server",
    val type: String = "vmess",
    val host: String = "",
    val port: Int = 443,
    @SerializedName("server_port")
    val serverPort: Int? = null,
    val rate: Double = 1.0,
    val tags: List<String>? = null,
    @SerializedName("is_online")
    val isOnline: Int? = null,
    @SerializedName("server_key")
    val serverKey: String? = null,
    @SerializedName("protocol_settings")
    val protocolSettings: Map<String, Any?>? = null,
    // 保留原始 JSON 供 ConfigBuilder 使用
)
