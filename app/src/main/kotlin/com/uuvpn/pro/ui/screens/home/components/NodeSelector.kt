package com.uuvpn.pro.ui.screens.home.components

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.uuvpn.pro.data.model.NodeModel
import com.uuvpn.pro.ui.components.GlassCard
import com.uuvpn.pro.ui.theme.*

/**
 * 当前选中节点的选择器卡片
 */
@Composable
fun NodeSelector(
    selectedNode: NodeModel?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GlassCard(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // 国旗区域
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .border(1.dp, SurfaceBorder, RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = selectedNode?.regionTag ?: "🌍",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (selectedNode != null) Primary else TextSecondary,
                )
            }

            Spacer(modifier = Modifier.width(12.dp))

            // 节点名称和详情
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = selectedNode?.name ?: "点击选择节点",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary,
                    maxLines = 1,
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = if (selectedNode != null)
                        "${selectedNode.displayType} · ${selectedNode.rate}x"
                    else "请先选择一个节点",
                    fontSize = 12.sp,
                    color = TextSecondary,
                )
            }

            Icon(
                imageVector = Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = TextSecondary,
            )
        }
    }
}
