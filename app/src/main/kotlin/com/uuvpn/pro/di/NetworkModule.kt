package com.uuvpn.pro.di

import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.uuvpn.pro.data.local.PrefsManager
import com.uuvpn.pro.data.remote.XboardApi
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Qualifier
import javax.inject.Singleton

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class AuthInterceptor

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class DynamicBaseUrlInterceptor

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideGson(): Gson = GsonBuilder()
        .setLenient()
        .create()

    /**
     * 动态 Base URL 拦截器
     *
     * 每次请求都从 PrefsManager 读取最新的 panelUrl，
     * 将请求 URL 的 host/port/scheme 替换为面板地址。
     * 这样即使用户在登录页修改了面板地址，也能立刻生效。
     */
    @Provides
    @Singleton
    @DynamicBaseUrlInterceptor
    fun provideDynamicBaseUrlInterceptor(prefs: PrefsManager): Interceptor {
        return Interceptor { chain ->
            val originalRequest = chain.request()
            val panelUrl = runBlocking { prefs.panelUrl.first() }

            if (panelUrl.isNotEmpty()) {
                val baseUrl = panelUrl.trimEnd('/') + "/"
                val newHttpUrl = baseUrl.toHttpUrlOrNull()
                if (newHttpUrl != null) {
                    // 用面板地址的 scheme + host + port 替换原始请求
                    val newUrl = originalRequest.url.newBuilder()
                        .scheme(newHttpUrl.scheme)
                        .host(newHttpUrl.host)
                        .port(newHttpUrl.port)
                        .build()
                    val newRequest = originalRequest.newBuilder()
                        .url(newUrl)
                        .build()
                    return@Interceptor chain.proceed(newRequest)
                }
            }

            chain.proceed(originalRequest)
        }
    }

    @Provides
    @Singleton
    @AuthInterceptor
    fun provideAuthInterceptor(prefs: PrefsManager): Interceptor {
        return Interceptor { chain ->
            val token = runBlocking { prefs.authToken.first() }
            val requestBuilder = chain.request().newBuilder()
                .addHeader("Content-Type", "application/json")

            if (!token.isNullOrEmpty()) {
                requestBuilder.addHeader("Authorization", "Bearer $token")
            }

            chain.proceed(requestBuilder.build())
        }
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(
        @AuthInterceptor authInterceptor: Interceptor,
        @DynamicBaseUrlInterceptor dynamicBaseUrlInterceptor: Interceptor,
    ): OkHttpClient {
        val loggingInterceptor = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BODY
        }

        return OkHttpClient.Builder()
            .addInterceptor(dynamicBaseUrlInterceptor)  // 先替换 URL
            .addInterceptor(authInterceptor)            // 再注入 token
            .addInterceptor(loggingInterceptor)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .build()
    }

    @Provides
    @Singleton
    fun provideRetrofit(
        okHttpClient: OkHttpClient,
        gson: Gson,
    ): Retrofit {
        // 占位 baseUrl（会被 DynamicBaseUrlInterceptor 动态替换）
        return Retrofit.Builder()
            .baseUrl("https://placeholder.local/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
    }

    @Provides
    @Singleton
    fun provideXboardApi(retrofit: Retrofit): XboardApi {
        return retrofit.create(XboardApi::class.java)
    }
}
