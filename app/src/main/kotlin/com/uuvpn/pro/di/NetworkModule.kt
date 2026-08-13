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
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideGson(): Gson = GsonBuilder()
        .setLenient()
        .create()

    @Provides
    @Singleton
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
    fun provideOkHttpClient(authInterceptor: Interceptor): OkHttpClient {
        val loggingInterceptor = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BODY
        }

        return OkHttpClient.Builder()
            .addInterceptor(authInterceptor)
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
        prefs: PrefsManager,
    ): Retrofit {
        // 获取面板 URL，默认使用占位地址（会在登录时动态切换）
        val baseUrl = runBlocking {
            val url = prefs.panelUrl.first()
            if (url.isNotEmpty()) url.trimEnd('/') + "/" else "https://localhost/"
        }

        return Retrofit.Builder()
            .baseUrl(baseUrl)
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
