package com.uuvpn.pro.ui.screens.home.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.uuvpn.pro.data.model.UserModel
import com.uuvpn.pro.ui.components.GlassCard
import com.uuvpn.pro.ui.theme.*

/**
 * 用户信息状态卡片
 */
@Composable
fun StatusCard(
    user: UserModel,
    modifier: Modifier = Modifier,
) {
    GlassCard(modifier = modifier.fillMaxWidth()) {
        Column {
            // 邮箱
            Text(
                text = user.email,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = TextPrimary,
            )

            Spacer(modifier = Modifier.height(10.dp))

            // 流量进度条
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                LinearProgressIndicator(
                    progress = { user.usagePercent.coerceIn(0f, 1f) },
                    modifier = Modifier
                        .weight(1f)
                        .height(6.dp)
                        .clip(RoundedCornerShape(3.dp)),
                    color = if (user.usagePercent > 0.9f) Error else Primary,
                    trackColor = SurfaceBorder,
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = "%.1f/%.0f GB".format(user.usedGB, user.totalGB),
                    fontSize = 12.sp,
                    color = TextSecondary,
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            // 到期时间
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "到期: ${user.expiredDateStr}",
                    fontSize = 12.sp,
                    color = if (user.isExpired) Error else TextSecondary,
                )
                if (user.isExpired) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(Error.copy(alpha = 0.15f))
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                    ) {
                        Text(
                            text = "已过期",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Error,
                        )
                    }
                }
            }
        }
    }
}
