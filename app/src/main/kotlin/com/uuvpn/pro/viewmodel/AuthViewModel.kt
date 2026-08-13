package com.uuvpn.pro.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.uuvpn.pro.data.local.PrefsManager
import com.uuvpn.pro.data.repository.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val prefs: PrefsManager,
) : ViewModel() {

    val isLoggedIn: StateFlow<Boolean> = prefs.isLoggedIn
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    val savedEmail: StateFlow<String> = prefs.loginEmail
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val savedPanelUrl: StateFlow<String> = prefs.panelUrl
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "https://www.yaochen.cc")

    private val _loginState = MutableStateFlow<LoginState>(LoginState.Idle)
    val loginState: StateFlow<LoginState> = _loginState.asStateFlow()

    fun login(panelUrl: String, email: String, password: String) {
        viewModelScope.launch {
            _loginState.value = LoginState.Loading
            val result = authRepository.login(panelUrl, email, password)
            _loginState.value = result.fold(
                onSuccess = { LoginState.Success },
                onFailure = { LoginState.Error(it.message ?: "登录失败") }
            )
        }
    }

    fun register(panelUrl: String, email: String, password: String, inviteCode: String?) {
        viewModelScope.launch {
            _loginState.value = LoginState.Loading
            val result = authRepository.register(panelUrl, email, password, inviteCode)
            _loginState.value = result.fold(
                onSuccess = { LoginState.Success },
                onFailure = { LoginState.Error(it.message ?: "注册失败") }
            )
        }
    }

    fun logout() {
        viewModelScope.launch {
            authRepository.logout()
        }
    }

    fun resetState() {
        _loginState.value = LoginState.Idle
    }
}

sealed class LoginState {
    data object Idle : LoginState()
    data object Loading : LoginState()
    data object Success : LoginState()
    data class Error(val message: String) : LoginState()
}
