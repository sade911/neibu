package com.uuvpn.pro.data.remote

import com.uuvpn.pro.data.remote.dto.*
import retrofit2.http.*

/**
 * Xboard 面板 API — Retrofit 接口
 */
interface XboardApi {

    // ===== Auth =====

    @POST("api/v1/passport/auth/login")
    suspend fun login(@Body request: LoginRequest): ApiResponse<LoginData>

    @POST("api/v1/passport/auth/register")
    suspend fun register(@Body request: RegisterRequest): ApiResponse<LoginData>

    // ===== User =====

    @GET("api/v1/user/info")
    suspend fun getUserInfo(): ApiResponse<UserInfoData>

    @GET("api/v1/user/getSubscribe")
    suspend fun getSubscribeInfo(): ApiResponse<SubscribeData>

    // ===== Servers =====

    @GET("api/v1/user/server/fetch")
    suspend fun fetchNodes(): ApiResponse<List<NodeData>>
}
