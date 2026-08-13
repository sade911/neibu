package com.uuvpn.pro.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "uuvpn_prefs")

/**
 * DataStore 偏好管理器
 */
@Singleton
class PrefsManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val store get() = context.dataStore

    // ===== Keys =====
    private object Keys {
        val PANEL_URL = stringPreferencesKey("panel_url")
        val AUTH_TOKEN = stringPreferencesKey("auth_token")
        val LOGIN_EMAIL = stringPreferencesKey("login_email")
        val SUBSCRIBE_URL = stringPreferencesKey("subscribe_url")
        val CURRENT_UUID = stringPreferencesKey("current_uuid")
        val SELECTED_NODE_ID = intPreferencesKey("selected_node_id")
        val AUTO_CONNECT = booleanPreferencesKey("auto_connect")
        val ROUTE_MODE = stringPreferencesKey("route_mode")         // bypass_cn / global
        val DNS_MODE = stringPreferencesKey("dns_mode")             // auto / custom
        val CUSTOM_DNS = stringPreferencesKey("custom_dns")
        val LOG_LEVEL = stringPreferencesKey("log_level")           // warn / info / debug
    }

    // ===== Auth =====
    val panelUrl: Flow<String> = store.data.map { it[Keys.PANEL_URL] ?: "" }
    val authToken: Flow<String?> = store.data.map { it[Keys.AUTH_TOKEN] }
    val loginEmail: Flow<String> = store.data.map { it[Keys.LOGIN_EMAIL] ?: "" }
    val subscribeUrl: Flow<String?> = store.data.map { it[Keys.SUBSCRIBE_URL] }
    val currentUuid: Flow<String?> = store.data.map { it[Keys.CURRENT_UUID] }
    val selectedNodeId: Flow<Int?> = store.data.map { it[Keys.SELECTED_NODE_ID] }
    val isLoggedIn: Flow<Boolean> = store.data.map { !it[Keys.AUTH_TOKEN].isNullOrEmpty() }

    // ===== Settings =====
    val autoConnect: Flow<Boolean> = store.data.map { it[Keys.AUTO_CONNECT] ?: false }
    val routeMode: Flow<String> = store.data.map { it[Keys.ROUTE_MODE] ?: "bypass_cn" }
    val dnsMode: Flow<String> = store.data.map { it[Keys.DNS_MODE] ?: "auto" }
    val customDns: Flow<String> = store.data.map { it[Keys.CUSTOM_DNS] ?: "https://8.8.8.8/dns-query" }
    val logLevel: Flow<String> = store.data.map { it[Keys.LOG_LEVEL] ?: "warn" }

    // ===== Setters =====
    suspend fun setPanelUrl(url: String) = store.edit { it[Keys.PANEL_URL] = url }
    suspend fun setAuthToken(token: String?) = store.edit {
        if (token != null) it[Keys.AUTH_TOKEN] = token else it.remove(Keys.AUTH_TOKEN)
    }
    suspend fun setLoginEmail(email: String) = store.edit { it[Keys.LOGIN_EMAIL] = email }
    suspend fun setSubscribeUrl(url: String?) = store.edit {
        if (url != null) it[Keys.SUBSCRIBE_URL] = url else it.remove(Keys.SUBSCRIBE_URL)
    }
    suspend fun setCurrentUuid(uuid: String?) = store.edit {
        if (uuid != null) it[Keys.CURRENT_UUID] = uuid else it.remove(Keys.CURRENT_UUID)
    }
    suspend fun setSelectedNodeId(id: Int?) = store.edit {
        if (id != null) it[Keys.SELECTED_NODE_ID] = id else it.remove(Keys.SELECTED_NODE_ID)
    }
    suspend fun setAutoConnect(enabled: Boolean) = store.edit { it[Keys.AUTO_CONNECT] = enabled }
    suspend fun setRouteMode(mode: String) = store.edit { it[Keys.ROUTE_MODE] = mode }
    suspend fun setDnsMode(mode: String) = store.edit { it[Keys.DNS_MODE] = mode }
    suspend fun setCustomDns(dns: String) = store.edit { it[Keys.CUSTOM_DNS] = dns }
    suspend fun setLogLevel(level: String) = store.edit { it[Keys.LOG_LEVEL] = level }

    // ===== Sync Getters =====
    suspend fun getAuthTokenSync(): String? = store.data.first()[Keys.AUTH_TOKEN]
    suspend fun getPanelUrlSync(): String = store.data.first()[Keys.PANEL_URL] ?: ""
    suspend fun getCurrentUuidSync(): String? = store.data.first()[Keys.CURRENT_UUID]

    // ===== Clear =====
    suspend fun clearAuth() = store.edit {
        it.remove(Keys.AUTH_TOKEN)
        it.remove(Keys.SUBSCRIBE_URL)
        it.remove(Keys.CURRENT_UUID)
        it.remove(Keys.SELECTED_NODE_ID)
    }
}
