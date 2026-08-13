package com.uuvpn.pro.data.repository

import com.uuvpn.pro.data.local.PrefsManager
import com.uuvpn.pro.data.remote.XboardApiService
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 认证仓库 — 登录/注册/UUID 提取
 */
@Singleton
class AuthRepository @Inject constructor(
    private val apiService: XboardApiService,
    private val prefs: PrefsManager,
) {
    /**
     * 登录 → 保存 token → 拉取订阅 → 提取 UUID
     */
    suspend fun login(panelUrl: String, email: String, password: String): Result<Unit> {
        prefs.setPanelUrl(panelUrl)
        val result = apiService.login(email, password)
        return result.fold(
            onSuccess = { token ->
                prefs.setAuthToken(token)
                prefs.setLoginEmail(email)
                // 拉取订阅信息
                fetchAndSaveSubscribe()
                Result.success(Unit)
            },
            onFailure = { Result.failure(it) }
        )
    }

    /**
     * 注册
     */
    suspend fun register(panelUrl: String, email: String, password: String, inviteCode: String?): Result<Unit> {
        prefs.setPanelUrl(panelUrl)
        val result = apiService.register(email, password, inviteCode)
        return result.fold(
            onSuccess = { token ->
                prefs.setAuthToken(token)
                prefs.setLoginEmail(email)
                fetchAndSaveSubscribe()
                Result.success(Unit)
            },
            onFailure = { Result.failure(it) }
        )
    }

    /**
     * 退出登录
     */
    suspend fun logout() {
        prefs.clearAuth()
    }

    /**
     * 获取订阅 URL + 提取 UUID
     */
    private suspend fun fetchAndSaveSubscribe() {
        val urlResult = apiService.getSubscribeUrl()
        urlResult.onSuccess { url ->
            prefs.setSubscribeUrl(url)
            extractUuid(url)
        }
    }

    /**
     * 从 Clash 订阅内容中提取 UUID / password
     */
    private suspend fun extractUuid(subscribeUrl: String) {
        val contentResult = apiService.downloadSubscription(subscribeUrl)
        contentResult.onSuccess { content ->
            // 尝试匹配 uuid: 或 password:
            val uuidRegex = Regex("uuid:\\s*([a-f0-9\\-]{36})", RegexOption.IGNORE_CASE)
            val pwdRegex = Regex("password:\\s*([a-f0-9\\-]{36})", RegexOption.IGNORE_CASE)

            val uuid = uuidRegex.find(content)?.groupValues?.get(1)
                ?: pwdRegex.find(content)?.groupValues?.get(1)

            if (uuid != null) {
                prefs.setCurrentUuid(uuid)
            }
        }
    }
}
