package com.uuvpn.pro.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.uuvpn.pro.data.local.PrefsManager
import com.uuvpn.pro.data.model.NodeModel
import com.uuvpn.pro.data.model.TrafficStats
import com.uuvpn.pro.data.model.UserModel
import com.uuvpn.pro.data.model.VpnState
import com.uuvpn.pro.data.repository.NodeRepository
import com.uuvpn.pro.data.repository.UserRepository
import com.uuvpn.pro.domain.VpnManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class VpnViewModel @Inject constructor(
    private val vpnManager: VpnManager,
    private val userRepository: UserRepository,
    private val nodeRepository: NodeRepository,
    private val prefs: PrefsManager,
) : ViewModel() {

    // ===== VPN State =====
    val vpnState: StateFlow<VpnState> = vpnManager.vpnState
    val trafficStats: StateFlow<TrafficStats> = vpnManager.trafficStats

    // ===== User =====
    private val _user = MutableStateFlow<UserModel?>(null)
    val user: StateFlow<UserModel?> = _user.asStateFlow()

    // ===== Selected Node =====
    private val _selectedNode = MutableStateFlow<NodeModel?>(null)
    val selectedNode: StateFlow<NodeModel?> = _selectedNode.asStateFlow()

    // ===== Connection Timer =====
    private val _connectionSeconds = MutableStateFlow(0L)
    val connectionSeconds: StateFlow<Long> = _connectionSeconds.asStateFlow()

    val connectionTimeFormatted: StateFlow<String> = _connectionSeconds.map { seconds ->
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        "%02d:%02d:%02d".format(h, m, s)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), "00:00:00")

    private var timerStartMs = 0L

    init {
        loadUserInfo()
        loadSelectedNode()
        observeVpnState()
    }

    private fun loadUserInfo() {
        viewModelScope.launch {
            userRepository.getUserInfo().onSuccess { _user.value = it }
        }
    }

    private fun loadSelectedNode() {
        viewModelScope.launch {
            prefs.selectedNodeId.collect { nodeId ->
                if (nodeId != null) {
                    _selectedNode.value = nodeRepository.getNodeById(nodeId)
                }
            }
        }
    }

    private fun observeVpnState() {
        viewModelScope.launch {
            vpnManager.vpnState.collect { state ->
                if (state == VpnState.CONNECTED && timerStartMs == 0L) {
                    timerStartMs = System.currentTimeMillis()
                    startTimer()
                } else if (state == VpnState.DISCONNECTED) {
                    timerStartMs = 0L
                    _connectionSeconds.value = 0L
                }
            }
        }
    }

    private fun startTimer() {
        viewModelScope.launch {
            while (isActive && vpnManager.vpnState.value == VpnState.CONNECTED) {
                _connectionSeconds.value = (System.currentTimeMillis() - timerStartMs) / 1000
                delay(1000)
            }
        }
    }

    fun refreshUserInfo() {
        loadUserInfo()
    }

    fun selectNode(node: NodeModel) {
        _selectedNode.value = node
        viewModelScope.launch {
            nodeRepository.setSelectedNode(node.id)
        }
    }

    fun toggleConnection() {
        viewModelScope.launch {
            val uuid = prefs.getCurrentUuidSync()
            vpnManager.toggleConnection(_selectedNode.value, uuid)
        }
    }
}
