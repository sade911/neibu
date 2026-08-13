package com.uuvpn.pro.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.uuvpn.pro.data.local.PrefsManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val prefs: PrefsManager,
) : ViewModel() {

    val autoConnect: StateFlow<Boolean> = prefs.autoConnect
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    val routeMode: StateFlow<String> = prefs.routeMode
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "bypass_cn")

    val dnsMode: StateFlow<String> = prefs.dnsMode
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "auto")

    val logLevel: StateFlow<String> = prefs.logLevel
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "warn")

    fun setAutoConnect(enabled: Boolean) {
        viewModelScope.launch { prefs.setAutoConnect(enabled) }
    }

    fun setRouteMode(mode: String) {
        viewModelScope.launch { prefs.setRouteMode(mode) }
    }

    fun setDnsMode(mode: String) {
        viewModelScope.launch { prefs.setDnsMode(mode) }
    }

    fun setLogLevel(level: String) {
        viewModelScope.launch { prefs.setLogLevel(level) }
    }
}
