package com.uuvpn.pro.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.uuvpn.pro.ui.theme.GradientPrimary
import com.uuvpn.pro.ui.theme.TextOnPrimary

/**
 * 渐变按钮
 */
@Composable
fun GradientButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    isLoading: Boolean = false,
    gradientColors: List<Color> = GradientPrimary,
    cornerRadius: Dp = 12.dp,
) {
    val alpha = if (enabled && !isLoading) 1f else 0.5f

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(RoundedCornerShape(cornerRadius))
            .background(
                brush = Brush.horizontalGradient(gradientColors),
                alpha = alpha,
            )
            .then(
                if (enabled && !isLoading) {
                    Modifier.noRippleClickable(onClick)
                } else {
                    Modifier
                }
            ),
        contentAlignment = Alignment.Center,
    ) {
        if (isLoading) {
            // 简单加载指示器
            val infiniteTransition = rememberInfiniteTransition(label = "loading")
            val dotAlpha by infiniteTransition.animateFloat(
                initialValue = 0.3f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(600),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "dotAlpha",
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(3) { index ->
                    val delay = index * 200
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(TextOnPrimary.copy(alpha = dotAlpha)),
                    )
                }
            }
        } else {
            Text(
                text = text,
                color = TextOnPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

/**
 * 无 ripple 的点击效果
 */
@Composable
fun Modifier.noRippleClickable(onClick: () -> Unit): Modifier {
    return this.then(
        Modifier.run {
            androidx.compose.foundation.clickable(
                indication = null,
                interactionSource = androidx.compose.foundation.interaction.MutableInteractionSource(),
                onClick = onClick,
            )
        }
    )
}
