package com.uuvpn.pro.ui.screens.nodes

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.uuvpn.pro.ui.screens.nodes.components.NodeCard
import com.uuvpn.pro.ui.screens.nodes.components.RegionFilter
import com.uuvpn.pro.ui.theme.*
import com.uuvpn.pro.viewmodel.NodeViewModel
import com.uuvpn.pro.viewmodel.VpnViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NodeListScreen(
    nodeViewModel: NodeViewModel = hiltViewModel(),
    vpnViewModel: VpnViewModel = hiltViewModel(),
) {
    val filteredNodes by nodeViewModel.filteredNodes.collectAsState()
    val regions by nodeViewModel.regions.collectAsState()
    val selectedRegion by nodeViewModel.selectedRegion.collectAsState()
    val searchQuery by nodeViewModel.searchQuery.collectAsState()
    val isPinging by nodeViewModel.isPinging.collectAsState()
    val isLoading by nodeViewModel.isLoading.collectAsState()
    val selectedNode by vpnViewModel.selectedNode.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
    ) {
        // ===== 顶部栏 =====
        TopAppBar(
            title = { Text("节点列表") },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = Surface,
                titleContentColor = TextPrimary,
            ),
            actions = {
                // 测速
                IconButton(
                    onClick = { nodeViewModel.pingAllNodes() },
                    enabled = !isPinging,
                ) {
                    if (isPinging) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = Primary,
                        )
                    } else {
                        Icon(Icons.Filled.Speed, "测速", tint = Primary)
                    }
                }
                // 刷新
                IconButton(onClick = { nodeViewModel.fetchNodes() }) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = Primary,
                        )
                    } else {
                        Icon(Icons.Filled.Refresh, "刷新", tint = Primary)
                    }
                }
            },
        )

        // ===== 搜索框 =====
        OutlinedTextField(
            value = searchQuery,
            onValueChange = { nodeViewModel.setSearchQuery(it) },
            placeholder = { Text("搜索节点名称或协议…", fontSize = 14.sp) },
            leadingIcon = { Icon(Icons.Filled.Search, null) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            singleLine = true,
            shape = RoundedCornerShape(12.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Primary,
                unfocusedBorderColor = SurfaceBorder,
                focusedContainerColor = SurfaceCard,
                unfocusedContainerColor = SurfaceCard,
                cursorColor = Primary,
                focusedLeadingIconColor = Primary,
                unfocusedLeadingIconColor = TextSecondary,
            ),
        )

        // ===== 地区过滤 =====
        RegionFilter(
            regions = regions,
            selectedRegion = selectedRegion,
            onRegionSelected = { nodeViewModel.setSelectedRegion(it) },
        )

        Spacer(modifier = Modifier.height(8.dp))

        // ===== 节点列表 =====
        if (filteredNodes.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text("暂无节点", color = TextSecondary)
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(filteredNodes, key = { it.id }) { node ->
                    NodeCard(
                        node = node,
                        isSelected = selectedNode?.id == node.id,
                        onClick = { vpnViewModel.selectNode(node) },
                    )
                }
                // 底部间距
                item { Spacer(modifier = Modifier.height(8.dp)) }
            }
        }
    }
}
