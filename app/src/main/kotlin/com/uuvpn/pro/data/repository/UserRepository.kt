package com.uuvpn.pro.data.repository

import com.uuvpn.pro.data.model.UserModel
import com.uuvpn.pro.data.remote.XboardApiService
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 用户仓库 — 用户信息获取
 */
@Singleton
class UserRepository @Inject constructor(
    private val apiService: XboardApiService,
) {
    suspend fun getUserInfo(): Result<UserModel> {
        return apiService.getUserInfo()
    }
}
