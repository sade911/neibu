package com.uuvpn.pro.ui.theme

import androidx.compose.ui.graphics.Color

// ============================================================
// 品牌主色
// ============================================================
val Primary = Color(0xFF00E5C3)          // Teal — 品牌色 / 已连接
val PrimaryVariant = Color(0xFF00BCD4)   // Cyan — 渐变端
val PrimaryDark = Color(0xFF00A896)      // 深 Teal — 按压态

// ============================================================
// 表面色（深色主题）
// ============================================================
val Surface = Color(0xFF0A0E1A)          // 深蓝黑 — 主背景
val SurfaceCard = Color(0xFF121829)      // 深蓝灰 — 卡片背景
val SurfaceCardLight = Color(0xFF1A2035) // 稍浅 — hover / elevated 卡片
val SurfaceBorder = Color(0xFF1E2540)    // 卡片边框
val SurfaceOverlay = Color(0xFF0F1425)   // 覆盖层

// ============================================================
// 功能色
// ============================================================
val Success = Color(0xFF00E5C3)          // 连接成功 / 低延迟
val Warning = Color(0xFFFFB74D)          // 中等延迟 / 警告
val Error = Color(0xFFFF4B6E)            // 错误 / 高延迟 / 断开
val Connecting = Color(0xFFFFD54F)       // 连接中 — 琥珀色
val Info = Color(0xFF64B5F6)             // 信息提示

// ============================================================
// 文字色
// ============================================================
val TextPrimary = Color(0xFFFFFFFF)      // 主要文字
val TextSecondary = Color(0xFF8B95B0)    // 次要文字
val TextTertiary = Color(0xFF4A5578)     // 禁用/提示文字
val TextOnPrimary = Color(0xFF0A0E1A)    // 主色上的文字

// ============================================================
// 渐变色组
// ============================================================
val GradientPrimary = listOf(Primary, PrimaryVariant)
val GradientDanger = listOf(Color(0xFFFF4B6E), Color(0xFFFF7043))
val GradientSurface = listOf(Surface, SurfaceCard)
val GradientGlow = listOf(Primary.copy(alpha = 0.3f), Primary.copy(alpha = 0.0f))

// ============================================================
// 协议标签色
// ============================================================
val ProtocolVless = Color(0xFF00E5C3)
val ProtocolTrojan = Color(0xFFFF7043)
val ProtocolVmess = Color(0xFF64B5F6)
val ProtocolHysteria = Color(0xFFCE93D8)
val ProtocolShadowsocks = Color(0xFFFFD54F)
val ProtocolTuic = Color(0xFF81C784)
val ProtocolWireguard = Color(0xFFE57373)
