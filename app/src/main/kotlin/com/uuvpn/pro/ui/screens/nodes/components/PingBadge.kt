package com.uuvpn.pro.ui.screens.nodes.components

import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.uuvpn.pro.ui.theme.*

@Composable
fun PingBadge(
    pingMs: Int?,
    modifier: Modifier = Modifier,
) {
    when {
        pingMs == null -> {
            CircularProgressIndicator(
                modifier = modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = TextSecondary,
            )
        }
        pingMs == -1 -> { /* 不显示 */ }
        else -> {
            val color = when {
                pingMs < 100 -> Success
                pingMs < 300 -> Warning
                else -> Error
            }
            val text = if (pingMs >= 999) "超时" else "${pingMs}ms"
            Text(
                text = text,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = color,
                modifier = modifier,
            )
        }
    }
}
