package com.uuvpn.pro.ui.screens.log

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.uuvpn.pro.ui.theme.*

data class LogEntry(
    val timestamp: String,
    val level: String,      // error / warn / info / debug
    val message: String,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogScreen(
    onNavigateBack: () -> Unit,
) {
    // 模拟日志数据（实际集成 libbox 后从 sing-box 获取）
    val logs = remember {
        mutableStateListOf(
            LogEntry("04:00:01", "info", "sing-box started"),
            LogEntry("04:00:01", "info", "tun interface created: tun0"),
            LogEntry("04:00:02", "info", "DNS server started on 127.0.0.1:6450"),
            LogEntry("04:00:02", "info", "mixed proxy started on 127.0.0.1:7890"),
            LogEntry("04:00:03", "info", "router: loaded geoip-cn (1234 rules)"),
            LogEntry("04:00:03", "info", "router: loaded geosite-cn (5678 domains)"),
            LogEntry("04:00:05", "warn", "router: fallback to direct for unmatched query"),
            LogEntry("04:00:10", "info", "outbound: proxy connection established"),
        )
    }

    var isPaused by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
        TopAppBar(
            title = { Text("运行日志") },
            navigationIcon = {
                IconButton(onClick = onNavigateBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回", tint = TextPrimary)
                }
            },
            actions = {
                IconButton(onClick = { isPaused = !isPaused }) {
                    Icon(
                        if (isPaused) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                        if (isPaused) "继续" else "暂停",
                        tint = Primary,
                    )
                }
                IconButton(onClick = { logs.clear() }) {
                    Icon(Icons.Filled.DeleteOutline, "清除", tint = Primary)
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = Surface,
                titleContentColor = TextPrimary,
            ),
        )

        // 日志列表
        if (logs.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text("暂无日志", color = TextSecondary)
            }
        } else {
            LazyColumn(
                state = listState,
                contentPadding = PaddingValues(8.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(logs) { entry ->
                    LogEntryRow(entry)
                }
            }
        }
    }
}

@Composable
private fun LogEntryRow(entry: LogEntry) {
    val levelColor = when (entry.level.lowercase()) {
        "error" -> Error
        "warn" -> Warning
        "info" -> Info
        "debug" -> TextTertiary
        else -> TextSecondary
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(SurfaceCard.copy(alpha = 0.5f))
            .padding(horizontal = 8.dp, vertical = 4.dp)
            .horizontalScroll(rememberScrollState()),
        verticalAlignment = Alignment.Top,
    ) {
        // 时间
        Text(
            text = entry.timestamp,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            color = TextTertiary,
        )
        Spacer(modifier = Modifier.width(8.dp))

        // 等级标签
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(2.dp))
                .background(levelColor.copy(alpha = 0.15f))
                .padding(horizontal = 4.dp, vertical = 1.dp),
        ) {
            Text(
                text = entry.level.uppercase().padEnd(5),
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                color = levelColor,
            )
        }
        Spacer(modifier = Modifier.width(8.dp))

        // 消息
        Text(
            text = entry.message,
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace,
            color = TextPrimary,
        )
    }
}
