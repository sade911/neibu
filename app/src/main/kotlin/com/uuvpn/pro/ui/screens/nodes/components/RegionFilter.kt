package com.uuvpn.pro.ui.screens.nodes.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.uuvpn.pro.ui.theme.*

@Composable
fun RegionFilter(
    regions: List<String>,
    selectedRegion: String,
    onRegionSelected: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // "全部"选项
        FilterChip(
            selected = selectedRegion == "全部",
            onClick = { onRegionSelected("全部") },
            label = { Text("全部", fontSize = 13.sp) },
            colors = FilterChipDefaults.filterChipColors(
                selectedContainerColor = Primary.copy(alpha = 0.2f),
                selectedLabelColor = Primary,
                containerColor = SurfaceCard,
                labelColor = TextSecondary,
            ),
            border = FilterChipDefaults.filterChipBorder(
                borderColor = if (selectedRegion == "全部") Primary else SurfaceBorder,
                selectedBorderColor = Primary,
                enabled = true,
                selected = selectedRegion == "全部",
            ),
        )

        // 各地区
        regions.forEach { region ->
            FilterChip(
                selected = selectedRegion == region,
                onClick = { onRegionSelected(region) },
                label = { Text(region, fontSize = 13.sp) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = Primary.copy(alpha = 0.2f),
                    selectedLabelColor = Primary,
                    containerColor = SurfaceCard,
                    labelColor = TextSecondary,
                ),
                border = FilterChipDefaults.filterChipBorder(
                    borderColor = if (selectedRegion == region) Primary else SurfaceBorder,
                    selectedBorderColor = Primary,
                    enabled = true,
                    selected = selectedRegion == region,
                ),
            )
        }
    }
}
