package com.uuvpn.pro.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.uuvpn.pro.ui.theme.Primary
import com.uuvpn.pro.ui.theme.Surface
import kotlin.math.cos
import kotlin.math.sin

/**
 * 动态背景 — 浮动光斑效果
 * 用于登录页等全屏背景
 */
@Composable
fun AnimatedBackground(
    modifier: Modifier = Modifier,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "bg")

    val offset1 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(20000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "offset1",
    )

    val offset2 by infiniteTransition.animateFloat(
        initialValue = 180f,
        targetValue = 540f,
        animationSpec = infiniteRepeatable(
            animation = tween(15000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "offset2",
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height

        // 背景
        drawRect(
            brush = Brush.verticalGradient(
                colors = listOf(Surface, Color(0xFF121829)),
            )
        )

        // 光斑 1 — 主色
        val rad1 = Math.toRadians(offset1.toDouble())
        val x1 = w * 0.3f + (w * 0.2f * cos(rad1)).toFloat()
        val y1 = h * 0.3f + (h * 0.15f * sin(rad1)).toFloat()
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(Primary.copy(alpha = 0.15f), Color.Transparent),
                center = Offset(x1, y1),
                radius = w * 0.5f,
            ),
            radius = w * 0.5f,
            center = Offset(x1, y1),
        )

        // 光斑 2 — 蓝紫色
        val rad2 = Math.toRadians(offset2.toDouble())
        val x2 = w * 0.7f + (w * 0.15f * sin(rad2)).toFloat()
        val y2 = h * 0.7f + (h * 0.1f * cos(rad2)).toFloat()
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(Color(0xFF6366F1).copy(alpha = 0.1f), Color.Transparent),
                center = Offset(x2, y2),
                radius = w * 0.4f,
            ),
            radius = w * 0.4f,
            center = Offset(x2, y2),
        )
    }
}
