package com.uuvpn.pro.ui.screens.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.uuvpn.pro.ui.theme.*
import com.uuvpn.pro.viewmodel.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val autoConnect by viewModel.autoConnect.collectAsState()
    val routeMode by viewModel.routeMode.collectAsState()
    val logLevel by viewModel.logLevel.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState()),
    ) {
        TopAppBar(
            title = { Text("设置") },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = Surface,
                titleContentColor = TextPrimary,
            ),
        )

        // ===== VPN 设置 =====
        SettingsSection(title = "VPN 设置") {
            // 路由模式
            SettingsRadioItem(
                icon = Icons.Filled.Route,
                title = "路由模式",
                subtitle = if (routeMode == "bypass_cn") "绕过中国大陆" else "全局代理",
                options = listOf("bypass_cn" to "绕过中国大陆", "global" to "全局代理"),
                selectedValue = routeMode,
                onValueChange = { viewModel.setRouteMode(it) },
            )

            HorizontalDivider(color = SurfaceBorder, modifier = Modifier.padding(horizontal = 16.dp))

            // 分应用代理
            SettingsClickItem(
                icon = Icons.Filled.Apps,
                title = "分应用代理",
                subtitle = "选择哪些应用通过 VPN",
                onClick = { /* TODO: 分应用选择页 */ },
            )
        }

        // ===== 通用设置 =====
        SettingsSection(title = "通用设置") {
            SettingsSwitchItem(
                icon = Icons.Filled.FlashOn,
                title = "自动连接",
                subtitle = "启动应用时自动连接",
                checked = autoConnect,
                onCheckedChange = { viewModel.setAutoConnect(it) },
            )
        }

        // ===== 高级设置 =====
        SettingsSection(title = "高级设置") {
            SettingsRadioItem(
                icon = Icons.AutoMirrored.Filled.Article,
                title = "日志等级",
                subtitle = logLevel.uppercase(),
                options = listOf("warn" to "Warn", "info" to "Info", "debug" to "Debug"),
                selectedValue = logLevel,
                onValueChange = { viewModel.setLogLevel(it) },
            )

            HorizontalDivider(color = SurfaceBorder, modifier = Modifier.padding(horizontal = 16.dp))

            SettingsClickItem(
                icon = Icons.Filled.DeleteOutline,
                title = "清除缓存",
                subtitle = "清除节点缓存和日志",
                onClick = { /* TODO */ },
            )
        }

        // ===== 关于 =====
        SettingsSection(title = "关于") {
            SettingsClickItem(
                icon = Icons.Filled.Info,
                title = "版本",
                subtitle = "1.0.0",
                onClick = { },
            )
        }

        Spacer(modifier = Modifier.height(32.dp))
    }
}

// ============================================================
// 设置组件
// ============================================================

@Composable
fun SettingsSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(
            text = title,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = Primary,
            modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
        )
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = SurfaceCard,
            tonalElevation = 0.dp,
        ) {
            Column(content = content)
        }
    }
}

@Composable
fun SettingsSwitchItem(
    icon: ImageVector,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = Primary, modifier = Modifier.size(22.dp))
        Spacer(modifier = Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = TextPrimary)
            Text(subtitle, fontSize = 12.sp, color = TextSecondary)
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = TextOnPrimary,
                checkedTrackColor = Primary,
                uncheckedThumbColor = TextSecondary,
                uncheckedTrackColor = SurfaceBorder,
            ),
        )
    }
}

@Composable
fun SettingsClickItem(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = Primary, modifier = Modifier.size(22.dp))
        Spacer(modifier = Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = TextPrimary)
            Text(subtitle, fontSize = 12.sp, color = TextSecondary)
        }
        Icon(Icons.Filled.ChevronRight, null, tint = TextTertiary, modifier = Modifier.size(20.dp))
    }
}

@Composable
fun SettingsRadioItem(
    icon: ImageVector,
    title: String,
    subtitle: String,
    options: List<Pair<String, String>>,
    selectedValue: String,
    onValueChange: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, null, tint = Primary, modifier = Modifier.size(22.dp))
            Spacer(modifier = Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = TextPrimary)
                Text(subtitle, fontSize = 12.sp, color = TextSecondary)
            }
            Icon(
                imageVector = if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                contentDescription = null,
                tint = TextTertiary,
                modifier = Modifier.size(20.dp),
            )
        }

        if (expanded) {
            options.forEach { (value, label) ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            onValueChange(value)
                            expanded = false
                        }
                        .padding(start = 52.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = selectedValue == value,
                        onClick = {
                            onValueChange(value)
                            expanded = false
                        },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = Primary,
                            unselectedColor = TextSecondary,
                        ),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(label, fontSize = 14.sp, color = TextPrimary)
                }
            }
        }
    }
}
