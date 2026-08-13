package com.uuvpn.pro.ui.screens.login

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.uuvpn.pro.ui.components.AnimatedBackground
import com.uuvpn.pro.ui.components.GradientButton
import com.uuvpn.pro.ui.theme.*
import com.uuvpn.pro.viewmodel.AuthViewModel
import com.uuvpn.pro.viewmodel.LoginState

@Composable
fun LoginScreen(
    onLoginSuccess: () -> Unit,
    onNavigateToRegister: () -> Unit,
    viewModel: AuthViewModel = hiltViewModel(),
) {
    val loginState by viewModel.loginState.collectAsState()
    val savedEmail by viewModel.savedEmail.collectAsState()
    val savedPanelUrl by viewModel.savedPanelUrl.collectAsState()

    var panelUrl by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var obscurePassword by remember { mutableStateOf(true) }

    // 初始化保存的值
    LaunchedEffect(savedPanelUrl) {
        if (panelUrl.isEmpty() && savedPanelUrl.isNotEmpty()) panelUrl = savedPanelUrl
        if (panelUrl.isEmpty()) panelUrl = "https://www.yaochen.cc"
    }
    LaunchedEffect(savedEmail) {
        if (email.isEmpty() && savedEmail.isNotEmpty()) email = savedEmail
    }

    // 登录成功后导航
    LaunchedEffect(loginState) {
        if (loginState is LoginState.Success) {
            viewModel.resetState()
            onLoginSuccess()
        }
    }

    val errorMessage = (loginState as? LoginState.Error)?.message
    val isLoading = loginState is LoginState.Loading

    Box(modifier = Modifier.fillMaxSize()) {
        // 动态背景
        AnimatedBackground()

        // 内容
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(24.dp)
                .statusBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(60.dp))

            // Logo
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(
                        brush = Brush.linearGradient(GradientPrimary),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Outlined.Lock,
                    contentDescription = null,
                    modifier = Modifier.size(44.dp),
                    tint = TextOnPrimary,
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // 品牌名
            Text(
                text = "UUVPN PRO",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = Primary,
                letterSpacing = 2.sp,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "安全 · 快速 · 稳定",
                fontSize = 14.sp,
                color = TextSecondary,
            )

            Spacer(modifier = Modifier.height(48.dp))

            // 面板地址
            OutlinedTextField(
                value = panelUrl,
                onValueChange = { panelUrl = it },
                label = { Text("面板地址") },
                leadingIcon = { Icon(Icons.Outlined.Dns, contentDescription = null) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = vpnTextFieldColors(),
                shape = RoundedCornerShape(12.dp),
            )

            Spacer(modifier = Modifier.height(16.dp))

            // 邮箱
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("邮箱") },
                leadingIcon = { Icon(Icons.Outlined.Email, contentDescription = null) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = vpnTextFieldColors(),
                shape = RoundedCornerShape(12.dp),
            )

            Spacer(modifier = Modifier.height(16.dp))

            // 密码
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("密码") },
                leadingIcon = { Icon(Icons.Outlined.Lock, contentDescription = null) },
                trailingIcon = {
                    IconButton(onClick = { obscurePassword = !obscurePassword }) {
                        Icon(
                            imageVector = if (obscurePassword) Icons.Outlined.VisibilityOff
                            else Icons.Outlined.Visibility,
                            contentDescription = null,
                        )
                    }
                },
                visualTransformation = if (obscurePassword) PasswordVisualTransformation()
                else VisualTransformation.None,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = vpnTextFieldColors(),
                shape = RoundedCornerShape(12.dp),
            )

            // 错误提示
            AnimatedVisibility(
                visible = errorMessage != null,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically(),
            ) {
                Spacer(modifier = Modifier.height(12.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(Error.copy(alpha = 0.1f))
                        .padding(12.dp),
                ) {
                    Text(
                        text = errorMessage ?: "",
                        color = Error,
                        fontSize = 13.sp,
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // 登录按钮
            GradientButton(
                text = "登 录",
                onClick = {
                    if (panelUrl.isNotBlank() && email.isNotBlank() && password.isNotBlank()) {
                        viewModel.login(panelUrl.trim(), email.trim(), password.trim())
                    }
                },
                isLoading = isLoading,
                enabled = !isLoading,
            )

            Spacer(modifier = Modifier.height(20.dp))

            // 注册链接
            Text(
                text = "还没有账号？注册",
                color = Primary,
                fontSize = 14.sp,
                modifier = Modifier.clickable { onNavigateToRegister() },
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun vpnTextFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = Primary,
    unfocusedBorderColor = SurfaceBorder,
    focusedLabelColor = Primary,
    unfocusedLabelColor = TextSecondary,
    cursorColor = Primary,
    focusedLeadingIconColor = Primary,
    unfocusedLeadingIconColor = TextSecondary,
    focusedTrailingIconColor = Primary,
    unfocusedTrailingIconColor = TextSecondary,
    focusedContainerColor = SurfaceCard,
    unfocusedContainerColor = SurfaceCard,
)
