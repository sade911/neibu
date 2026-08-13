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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RegisterScreen(
    onRegisterSuccess: () -> Unit,
    onNavigateBack: () -> Unit,
    viewModel: AuthViewModel = hiltViewModel(),
) {
    val loginState by viewModel.loginState.collectAsState()

    var panelUrl by remember { mutableStateOf("https://www.yaochen.cc") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var inviteCode by remember { mutableStateOf("") }
    var obscurePassword by remember { mutableStateOf(true) }

    LaunchedEffect(loginState) {
        if (loginState is LoginState.Success) {
            viewModel.resetState()
            onRegisterSuccess()
        }
    }

    val errorMessage = (loginState as? LoginState.Error)?.message
    val isLoading = loginState is LoginState.Loading

    Box(modifier = Modifier.fillMaxSize()) {
        AnimatedBackground()

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(24.dp)
                .statusBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // 返回按钮
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onNavigateBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回", tint = TextPrimary)
                }
            }

            Spacer(modifier = Modifier.height(32.dp))

            Text(
                text = "创建账号",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "注册后即可使用 UUVPN PRO",
                fontSize = 14.sp,
                color = TextSecondary,
            )

            Spacer(modifier = Modifier.height(36.dp))

            // 面板地址
            OutlinedTextField(
                value = panelUrl,
                onValueChange = { panelUrl = it },
                label = { Text("面板地址") },
                leadingIcon = { Icon(Icons.Outlined.Dns, null) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = registerTextFieldColors(),
                shape = RoundedCornerShape(12.dp),
            )
            Spacer(modifier = Modifier.height(16.dp))

            // 邮箱
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("邮箱") },
                leadingIcon = { Icon(Icons.Outlined.Email, null) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = registerTextFieldColors(),
                shape = RoundedCornerShape(12.dp),
            )
            Spacer(modifier = Modifier.height(16.dp))

            // 密码
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("密码") },
                leadingIcon = { Icon(Icons.Outlined.Lock, null) },
                trailingIcon = {
                    IconButton(onClick = { obscurePassword = !obscurePassword }) {
                        Icon(
                            if (obscurePassword) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                            null,
                        )
                    }
                },
                visualTransformation = if (obscurePassword) PasswordVisualTransformation()
                else VisualTransformation.None,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = registerTextFieldColors(),
                shape = RoundedCornerShape(12.dp),
            )
            Spacer(modifier = Modifier.height(16.dp))

            // 邀请码
            OutlinedTextField(
                value = inviteCode,
                onValueChange = { inviteCode = it },
                label = { Text("邀请码（选填）") },
                leadingIcon = { Icon(Icons.Outlined.CardGiftcard, null) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = registerTextFieldColors(),
                shape = RoundedCornerShape(12.dp),
            )

            // 错误
            AnimatedVisibility(visible = errorMessage != null) {
                Spacer(modifier = Modifier.height(12.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(Error.copy(alpha = 0.1f))
                        .padding(12.dp),
                ) {
                    Text(errorMessage ?: "", color = Error, fontSize = 13.sp)
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            GradientButton(
                text = "注 册",
                onClick = {
                    if (panelUrl.isNotBlank() && email.isNotBlank() && password.isNotBlank()) {
                        viewModel.register(
                            panelUrl.trim(), email.trim(), password.trim(),
                            inviteCode.trim().ifBlank { null },
                        )
                    }
                },
                isLoading = isLoading,
                enabled = !isLoading,
            )

            Spacer(modifier = Modifier.height(20.dp))

            Text(
                text = "已有账号？登录",
                color = Primary,
                fontSize = 14.sp,
                modifier = Modifier.clickable { onNavigateBack() },
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun registerTextFieldColors() = OutlinedTextFieldDefaults.colors(
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
