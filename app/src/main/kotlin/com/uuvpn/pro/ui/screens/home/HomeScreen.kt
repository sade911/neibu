package com.uuvpn.pro.ui.screens.home

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.uuvpn.pro.data.model.VpnState
import com.uuvpn.pro.ui.screens.home.components.*
import com.uuvpn.pro.ui.theme.*
import com.uuvpn.pro.viewmodel.VpnViewModel

@Composable
fun HomeScreen(
    viewModel: VpnViewModel = hiltViewModel(),
) {
    val vpnState by viewModel.vpnState.collectAsState()
    val user by viewModel.user.collectAsState()
    val selectedNode by viewModel.selectedNode.collectAsState()
    val trafficStats by viewModel.trafficStats.collectAsState()
    val connectionTime by viewModel.connectionTimeFormatted.collectAsState()

    val isConnected = vpnState == VpnState.CONNECTED
    val isConnecting = vpnState == VpnState.CONNECTING

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp)
            .statusBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // ===== App Bar =====
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.Bolt,
                contentDescription = null,
                tint = Primary,
                modifier = Modifier.size(28.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "UUVPN PRO",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = Primary,
                letterSpacing = 1.5.sp,
            )
        }

        // ===== 用户信息卡片 =====
        user?.let { u ->
            StatusCard(user = u)
        }

        Spacer(modifier = Modifier.weight(1f))

        // ===== 连接按钮 =====
        ConnectButton(
            state = vpnState,
            onClick = { viewModel.toggleConnection() },
        )

        Spacer(modifier = Modifier.height(16.dp))

        // ===== 状态文字 =====
        Text(
            text = when (vpnState) {
                VpnState.CONNECTED -> "已连接"
                VpnState.CONNECTING -> "连接中…"
                VpnState.DISCONNECTING -> "断开中…"
                VpnState.DISCONNECTED -> "未连接"
            },
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = when (vpnState) {
                VpnState.CONNECTED -> Success
                VpnState.CONNECTING -> Connecting
                else -> TextSecondary
            },
        )

        // ===== 连接时间 =====
        if (isConnected) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = connectionTime,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = TextSecondary,
                letterSpacing = 1.sp,
            )
        }

        // ===== 流量统计 =====
        if (isConnected) {
            Spacer(modifier = Modifier.height(8.dp))
            TrafficStatsView(stats = trafficStats)
        }

        Spacer(modifier = Modifier.weight(1f))

        // ===== 当前节点选择器 =====
        NodeSelector(
            selectedNode = selectedNode,
            onClick = { /* 由底部导航切换到节点页 */ },
        )

        Spacer(modifier = Modifier.height(16.dp))
    }
}
