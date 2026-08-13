package com.uuvpn.pro.ui.screens.account

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.uuvpn.pro.ui.components.GlassCard
import com.uuvpn.pro.ui.theme.*
import com.uuvpn.pro.viewmodel.AuthViewModel
import com.uuvpn.pro.viewmodel.VpnViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(
    onLogout: () -> Unit,
    vpnViewModel: VpnViewModel = hiltViewModel(),
    authViewModel: AuthViewModel = hiltViewModel(),
) {
    val user by vpnViewModel.user.collectAsState()
    var showLogoutDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState()),
    ) {
        TopAppBar(
            title = { Text("账户") },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = Surface,
                titleContentColor = TextPrimary,
            ),
        )

        // ===== 用户头像区 =====
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // 渐变头像
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(
                        brush = Brush.linearGradient(GradientPrimary),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Person,
                    contentDescription = null,
                    tint = TextOnPrimary,
                    modifier = Modifier.size(36.dp),
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = user?.email ?: "未登录",
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = TextPrimary,
            )
        }

        // ===== 流量环形图 =====
        user?.let { u ->
            GlassCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // 环形进度图
                    Box(modifier = Modifier.size(80.dp)) {
                        Canvas(modifier = Modifier.fillMaxSize()) {
                            val strokeWidth = 8.dp.toPx()
                            val radius = (size.minDimension - strokeWidth) / 2
                            val topLeft = Offset(
                                (size.width - radius * 2) / 2,
                                (size.height - radius * 2) / 2,
                            )
                            val arcSize = Size(radius * 2, radius * 2)

                            // 背景环
                            drawArc(
                                color = SurfaceBorder,
                                startAngle = -90f,
                                sweepAngle = 360f,
                                useCenter = false,
                                topLeft = topLeft,
                                size = arcSize,
                                style = Stroke(strokeWidth, cap = StrokeCap.Round),
                            )

                            // 进度环
                            val progress = u.usagePercent.coerceIn(0f, 1f)
                            drawArc(
                                brush = Brush.sweepGradient(
                                    colors = if (progress > 0.9f)
                                        listOf(Error, Warning)
                                    else
                                        listOf(Primary, PrimaryVariant),
                                ),
                                startAngle = -90f,
                                sweepAngle = 360f * progress,
                                useCenter = false,
                                topLeft = topLeft,
                                size = arcSize,
                                style = Stroke(strokeWidth, cap = StrokeCap.Round),
                            )
                        }

                        // 中间百分比
                        Text(
                            text = "%.0f%%".format(u.usagePercent * 100),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                            modifier = Modifier.align(Alignment.Center),
                        )
                    }

                    Spacer(modifier = Modifier.width(20.dp))

                    Column {
                        Text(
                            text = "流量使用",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextPrimary,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "%.1f GB / %.0f GB".format(u.usedGB, u.totalGB),
                            fontSize = 13.sp,
                            color = TextSecondary,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "到期: ${u.expiredDateStr}",
                            fontSize = 13.sp,
                            color = if (u.isExpired) Error else TextSecondary,
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // ===== 操作按钮 =====
        Column(modifier = Modifier.padding(horizontal = 16.dp)) {
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = SurfaceCard,
            ) {
                Column {
                    AccountActionItem(
                        icon = Icons.Filled.ContentCopy,
                        title = "复制订阅链接",
                        onClick = { /* TODO: 复制到剪贴板 */ },
                    )
                    HorizontalDivider(color = SurfaceBorder, modifier = Modifier.padding(horizontal = 16.dp))
                    AccountActionItem(
                        icon = Icons.Filled.Refresh,
                        title = "刷新订阅",
                        onClick = { vpnViewModel.refreshUserInfo() },
                    )
                    HorizontalDivider(color = SurfaceBorder, modifier = Modifier.padding(horizontal = 16.dp))
                    AccountActionItem(
                        icon = Icons.Filled.Logout,
                        title = "退出登录",
                        isDestructive = true,
                        onClick = { showLogoutDialog = true },
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(32.dp))
    }

    // ===== 退出确认对话框 =====
    if (showLogoutDialog) {
        AlertDialog(
            onDismissRequest = { showLogoutDialog = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        showLogoutDialog = false
                        authViewModel.logout()
                        onLogout()
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = Error),
                ) {
                    Text("确定")
                }
            },
            dismissButton = {
                TextButton(onClick = { showLogoutDialog = false }) {
                    Text("取消")
                }
            },
            title = { Text("退出登录") },
            text = { Text("确定要退出登录吗？") },
            containerColor = SurfaceCard,
            titleContentColor = TextPrimary,
            textContentColor = TextSecondary,
        )
    }
}

@Composable
private fun AccountActionItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    isDestructive: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon, null,
            tint = if (isDestructive) Error else Primary,
            modifier = Modifier.size(22.dp),
        )
        Spacer(modifier = Modifier.width(14.dp))
        Text(
            text = title,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = if (isDestructive) Error else TextPrimary,
            modifier = Modifier.weight(1f),
        )
        Icon(Icons.Filled.ChevronRight, null, tint = TextTertiary, modifier = Modifier.size(20.dp))
    }
}
