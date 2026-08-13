package com.uuvpn.pro.ui.screens.nodes.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.uuvpn.pro.data.model.NodeModel
import com.uuvpn.pro.ui.theme.*

@Composable
fun NodeCard(
    node: NodeModel,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val borderColor by animateColorAsState(
        targetValue = if (isSelected) Primary else SurfaceBorder,
        animationSpec = tween(200),
        label = "border",
    )
    val bgColor by animateColorAsState(
        targetValue = if (isSelected) Primary.copy(alpha = 0.08f) else SurfaceCard,
        animationSpec = tween(200),
        label = "bg",
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(bgColor)
            .border(
                width = if (isSelected) 1.5.dp else 1.dp,
                color = borderColor,
                shape = RoundedCornerShape(14.dp),
            )
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // 地区标签
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (isSelected) Primary.copy(alpha = 0.15f) else Surface),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = node.regionTag,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (isSelected) Primary else TextSecondary,
                )
            }

            Spacer(modifier = Modifier.width(12.dp))

            // 名称 + 协议
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = node.name,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isSelected) Primary else TextPrimary,
                    maxLines = 1,
                )
                Spacer(modifier = Modifier.height(2.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ProtocolBadge(type = node.displayType)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "${node.rate}x",
                        fontSize = 11.sp,
                        color = TextSecondary,
                    )
                    node.tagList.take(2).forEach { tag ->
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = tag,
                            fontSize = 11.sp,
                            color = TextSecondary,
                        )
                    }
                }
            }

            // Ping
            PingBadge(pingMs = node.pingMs)

            if (isSelected) {
                Spacer(modifier = Modifier.width(8.dp))
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = Primary,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

@Composable
fun ProtocolBadge(type: String) {
    val color = when (type.lowercase()) {
        "vless" -> ProtocolVless
        "trojan" -> ProtocolTrojan
        "vmess" -> ProtocolVmess
        "hysteria", "hysteria2" -> ProtocolHysteria
        "shadowsocks" -> ProtocolShadowsocks
        "tuic" -> ProtocolTuic
        "wireguard" -> ProtocolWireguard
        else -> Primary
    }

    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(color.copy(alpha = 0.1f))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    ) {
        Text(
            text = type,
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            color = color,
        )
    }
}
