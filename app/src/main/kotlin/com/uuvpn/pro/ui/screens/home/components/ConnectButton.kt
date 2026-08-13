package com.uuvpn.pro.ui.screens.home.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material3.Icon
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.uuvpn.pro.data.model.VpnState
import com.uuvpn.pro.ui.theme.*
import kotlin.math.cos
import kotlin.math.sin

/**
 * 主连接按钮 — 3层动画效果
 *
 * - 外圈: 旋转轨道弧线
 * - 中圈: 脉冲呼吸光环
 * - 内圈: 电源图标
 */
@Composable
fun ConnectButton(
    state: VpnState,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isConnected = state == VpnState.CONNECTED
    val isConnecting = state == VpnState.CONNECTING

    val primaryColor = when (state) {
        VpnState.CONNECTED -> Primary
        VpnState.CONNECTING -> Connecting
        VpnState.DISCONNECTING -> Warning
        VpnState.DISCONNECTED -> TextSecondary.copy(alpha = 0.4f)
    }

    // 外圈旋转动画
    val infiniteTransition = rememberInfiniteTransition(label = "orbit")
    val orbitAngle by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(3000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "orbitAngle",
    )

    // 脉冲呼吸动画
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 0.85f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulseScale",
    )

    // 发光动画
    val glowAlpha by infiniteTransition.animateFloat(
        initialValue = if (isConnected) 0.2f else 0f,
        targetValue = if (isConnected) 0.5f else 0f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glowAlpha",
    )

    val buttonSize = 140.dp

    Box(
        modifier = modifier
            .size(buttonSize)
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() },
                onClick = onClick,
                enabled = !state.isTransitioning,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.size(buttonSize)) {
            val center = Offset(size.width / 2, size.height / 2)
            val outerRadius = size.width / 2

            // 外圈发光
            if (isConnected || isConnecting) {
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            primaryColor.copy(alpha = glowAlpha),
                            Color.Transparent,
                        ),
                        center = center,
                        radius = outerRadius * 1.3f,
                    ),
                    radius = outerRadius * 1.3f,
                    center = center,
                )
            }

            // 外圈弧线（旋转）
            if (isConnected || isConnecting) {
                drawArc(
                    color = primaryColor.copy(alpha = 0.6f),
                    startAngle = orbitAngle,
                    sweepAngle = 90f,
                    useCenter = false,
                    style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round),
                    topLeft = Offset(
                        center.x - outerRadius * 0.95f,
                        center.y - outerRadius * 0.95f,
                    ),
                    size = androidx.compose.ui.geometry.Size(
                        outerRadius * 1.9f,
                        outerRadius * 1.9f,
                    ),
                )
            }

            // 中圈边框
            val midRadius = outerRadius * pulseScale * 0.85f
            drawCircle(
                color = primaryColor,
                radius = midRadius,
                center = center,
                style = Stroke(width = 3.dp.toPx()),
            )

            // 内圈填充
            val innerRadius = outerRadius * 0.72f
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(
                        primaryColor.copy(alpha = 0.15f),
                        primaryColor.copy(alpha = 0.03f),
                    ),
                    center = center,
                    radius = innerRadius,
                ),
                radius = innerRadius,
                center = center,
            )
        }

        // 图标或加载指示器
        if (isConnecting) {
            CircularProgressIndicator(
                modifier = Modifier.size(36.dp),
                color = Connecting,
                strokeWidth = 3.dp,
            )
        } else {
            Icon(
                imageVector = Icons.Filled.PowerSettingsNew,
                contentDescription = "连接",
                modifier = Modifier.size(48.dp),
                tint = if (isConnected) Primary else TextSecondary.copy(alpha = 0.5f),
            )
        }
    }
}
