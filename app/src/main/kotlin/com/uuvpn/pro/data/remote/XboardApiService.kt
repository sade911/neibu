package com.uuvpn.pro.data.remote

import com.google.gson.Gson
import com.uuvpn.pro.data.local.PrefsManager
import com.uuvpn.pro.data.model.NodeModel
import com.uuvpn.pro.data.model.UserModel
import com.uuvpn.pro.data.remote.dto.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Xboard API 服务封装层
 *
 * 处理 token 注入、DTO → Model 映射、错误处理
 */
@Singleton
class XboardApiService @Inject constructor(
    private val api: XboardApi,
    private val prefs: PrefsManager,
    private val okHttpClient: OkHttpClient,
    private val gson: Gson,
) {
    // ============================================================
    // Auth
    // ============================================================

    suspend fun login(email: String, password: String): Result<String> {
        return try {
            val resp = api.login(LoginRequest(email, password))
            val token = resp.data?.authToken
            if (token != null) {
                Result.success(token)
            } else {
                Result.failure(Exception(resp.message ?: "登录失败"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun register(email: String, password: String, inviteCode: String?): Result<String> {
        return try {
            val resp = api.register(RegisterRequest(email, password, inviteCode))
            val token = resp.data?.authToken
            if (token != null) {
                Result.success(token)
            } else {
                Result.failure(Exception(resp.message ?: "注册失败"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // ============================================================
    // User
    // ============================================================

    suspend fun getUserInfo(): Result<UserModel> {
        return try {
            val resp = api.getUserInfo()
            val data = resp.data ?: return Result.failure(Exception("无用户数据"))
            Result.success(
                UserModel(
                    id = data.id,
                    email = data.email,
                    planId = data.planId,
                    expiredAt = data.expiredAt,
                    transferEnable = data.transferEnable,
                    transferUsed = data.d + data.u,
                    token = data.token,
                )
            )
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getSubscribeUrl(): Result<String> {
        return try {
            val resp = api.getSubscribeInfo()
            val url = resp.data?.subscribeUrl
            if (url != null) Result.success(url)
            else Result.failure(Exception("无订阅链接"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // ============================================================
    // Nodes
    // ============================================================

    suspend fun fetchNodes(): Result<List<NodeModel>> {
        return try {
            val resp = api.fetchNodes()
            val nodeList = resp.data ?: emptyList()
            val models = nodeList.map { dto ->
                NodeModel(
                    id = dto.id,
                    name = dto.name,
                    type = dto.type,
                    host = dto.host,
                    port = dto.port,
                    serverPort = dto.serverPort ?: dto.port,
                    rate = dto.rate,
                    flag = NodeModel.getFlagFromName(dto.name),
                    tags = dto.tags?.joinToString(",") ?: "",
                    rawConfigJson = gson.toJson(dto),
                    isOnline = dto.isOnline == 1,
                )
            }
            Result.success(models)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // ============================================================
    // Subscription Download
    // ============================================================

    /**
     * 下载订阅内容（Clash YAML），从中提取 UUID
     */
    suspend fun downloadSubscription(subscribeUrl: String): Result<String> {
        return withContext(Dispatchers.IO) {
            try {
                val url = if (subscribeUrl.contains("?")) {
                    "$subscribeUrl&flag=clash"
                } else {
                    "$subscribeUrl?flag=clash"
                }
                val request = Request.Builder().url(url).build()
                val response = okHttpClient.newCall(request).execute()
                if (response.isSuccessful) {
                    Result.success(response.body?.string() ?: "")
                } else {
                    Result.failure(Exception("HTTP ${response.code}"))
                }
            } catch (e: Exception) {
                Result.failure(e)
            }
        }
    }
}
