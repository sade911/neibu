package com.uuvpn.pro.ui.screens.home.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.uuvpn.pro.data.model.TrafficStats
import com.uuvpn.pro.ui.theme.Primary
import com.uuvpn.pro.ui.theme.TextSecondary

/**
 * 流量统计显示
 */
@Composable
fun TrafficStatsView(
    stats: TrafficStats,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(24.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 上传
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Filled.ArrowUpward,
                contentDescription = "上传",
                tint = Primary.copy(alpha = 0.7f),
                modifier = Modifier.size(14.dp),
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = stats.uploadFormatted,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = TextSecondary,
            )
        }

        // 下载
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Filled.ArrowDownward,
                contentDescription = "下载",
                tint = Primary.copy(alpha = 0.7f),
                modifier = Modifier.size(14.dp),
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = stats.downloadFormatted,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = TextSecondary,
            )
        }
    }
}
