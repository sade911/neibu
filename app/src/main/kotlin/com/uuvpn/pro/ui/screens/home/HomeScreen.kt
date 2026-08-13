package com.uuvpn.pro.ui.screens.home

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.uuvpn.pro.data.model.VpnState
import com.uuvpn.pro.ui.screens.home.components.*
import com.uuvpn.pro.ui.theme.*
import com.uuvpn.pro.viewmodel.VpnViewModel
import kotlinx.coroutines.flow.collectLatest

@Composable
fun HomeScreen(
    onNavigateToNodes: () -> Unit = {},
    viewModel: VpnViewModel = hiltViewModel(),
) {
    val vpnState by viewModel.vpnState.collectAsState()
    val user by viewModel.user.collectAsState()
    val selectedNode by viewModel.selectedNode.collectAsState()
    val trafficStats by viewModel.trafficStats.collectAsState()
    val connectionTime by viewModel.connectionTimeFormatted.collectAsState()
    val context = LocalContext.current

    val isConnected = vpnState == VpnState.CONNECTED

    // ===== VPN 权限请求 =====
    val vpnPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            // 用户授权了 VPN 权限，执行连接
            viewModel.toggleConnection()
        } else {
            Toast.makeText(context, "需要 VPN 权限才能连接", Toast.LENGTH_SHORT).show()
        }
    }

    // 监听 Toast 消息
    LaunchedEffect(Unit) {
        viewModel.toastMessage.collectLatest { message ->
            Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
        }
    }

    // 处理连接按钮点击
    val handleConnectClick: () -> Unit = {
        if (vpnState == VpnState.CONNECTED || vpnState == VpnState.CONNECTING) {
            // 断开不需要权限检查
            viewModel.toggleConnection()
        } else {
            // 连接前先检查 VPN 权限
            val prepareIntent = VpnService.prepare(context)
            if (prepareIntent != null) {
                // 需要用户授权
                vpnPermissionLauncher.launch(prepareIntent)
            } else {
                // 已有权限，直接连接
                viewModel.toggleConnection()
            }
        }
    }

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
            onClick = handleConnectClick,
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
            onClick = onNavigateToNodes,
        )

        Spacer(modifier = Modifier.height(16.dp))
    }
}
