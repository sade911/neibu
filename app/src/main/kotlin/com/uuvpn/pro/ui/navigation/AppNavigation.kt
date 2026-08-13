package com.uuvpn.pro.ui.navigation

import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.uuvpn.pro.ui.screens.account.AccountScreen
import com.uuvpn.pro.ui.screens.home.HomeScreen
import com.uuvpn.pro.ui.screens.log.LogScreen
import com.uuvpn.pro.ui.screens.login.LoginScreen
import com.uuvpn.pro.ui.screens.login.RegisterScreen
import com.uuvpn.pro.ui.screens.nodes.NodeListScreen
import com.uuvpn.pro.ui.screens.settings.SettingsScreen
import com.uuvpn.pro.ui.theme.*
import com.uuvpn.pro.viewmodel.AuthViewModel

// ============================================================
// 路由定义
// ============================================================
object Routes {
    const val LOGIN = "login"
    const val REGISTER = "register"
    const val MAIN = "main"
    const val HOME = "home"
    const val NODES = "nodes"
    const val ACCOUNT = "account"
    const val SETTINGS = "settings"
    const val LOG = "log"
}

// ============================================================
// 底部导航项
// ============================================================
data class BottomNavItem(
    val route: String,
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
)

val bottomNavItems = listOf(
    BottomNavItem(Routes.HOME, "首页", Icons.Filled.Home, Icons.Outlined.Home),
    BottomNavItem(Routes.NODES, "节点", Icons.Filled.Storage, Icons.Outlined.Storage),
    BottomNavItem(Routes.ACCOUNT, "账户", Icons.Filled.Person, Icons.Outlined.Person),
    BottomNavItem(Routes.SETTINGS, "设置", Icons.Filled.Settings, Icons.Outlined.Settings),
)

// ============================================================
// 顶层导航
// ============================================================
@Composable
fun AppNavigation() {
    val authViewModel: AuthViewModel = hiltViewModel()
    val isLoggedIn by authViewModel.isLoggedIn.collectAsState()

    val navController = rememberNavController()

    NavHost(
        navController = navController,
        startDestination = if (isLoggedIn) Routes.MAIN else Routes.LOGIN,
        enterTransition = { fadeIn(animationSpec = tween(300)) },
        exitTransition = { fadeOut(animationSpec = tween(300)) },
    ) {
        // 登录
        composable(Routes.LOGIN) {
            LoginScreen(
                onLoginSuccess = {
                    navController.navigate(Routes.MAIN) {
                        popUpTo(Routes.LOGIN) { inclusive = true }
                    }
                },
                onNavigateToRegister = {
                    navController.navigate(Routes.REGISTER)
                },
            )
        }

        // 注册
        composable(Routes.REGISTER) {
            RegisterScreen(
                onRegisterSuccess = {
                    navController.navigate(Routes.MAIN) {
                        popUpTo(Routes.LOGIN) { inclusive = true }
                    }
                },
                onNavigateBack = { navController.popBackStack() },
            )
        }

        // 主界面（含底部导航）
        composable(Routes.MAIN) {
            MainScreen(
                onLogout = {
                    navController.navigate(Routes.LOGIN) {
                        popUpTo(0) { inclusive = true }
                    }
                },
            )
        }

        // 日志页（从设置进入）
        composable(Routes.LOG) {
            LogScreen(onNavigateBack = { navController.popBackStack() })
        }
    }
}

// ============================================================
// 主界面 — 含底部导航
// ============================================================
@Composable
fun MainScreen(
    onLogout: () -> Unit,
) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    Scaffold(
        containerColor = Surface,
        bottomBar = {
            NavigationBar(
                containerColor = SurfaceCard,
                contentColor = TextPrimary,
                tonalElevation = androidx.compose.ui.unit.dp.times(0),
            ) {
                bottomNavItems.forEach { item ->
                    val selected = currentDestination?.hierarchy?.any { it.route == item.route } == true
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            navController.navigate(item.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = {
                            Icon(
                                imageVector = if (selected) item.selectedIcon else item.unselectedIcon,
                                contentDescription = item.label,
                            )
                        },
                        label = { Text(item.label, style = MaterialTheme.typography.labelSmall) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = Primary,
                            selectedTextColor = Primary,
                            unselectedIconColor = TextSecondary,
                            unselectedTextColor = TextSecondary,
                            indicatorColor = Primary.copy(alpha = 0.12f),
                        ),
                    )
                }
            }
        },
    ) { paddingValues ->
        NavHost(
            navController = navController,
            startDestination = Routes.HOME,
            modifier = Modifier.padding(paddingValues),
            enterTransition = { fadeIn(animationSpec = tween(200)) },
            exitTransition = { fadeOut(animationSpec = tween(200)) },
        ) {
            composable(Routes.HOME) {
                HomeScreen()
            }
            composable(Routes.NODES) {
                NodeListScreen()
            }
            composable(Routes.ACCOUNT) {
                AccountScreen(onLogout = onLogout)
            }
            composable(Routes.SETTINGS) {
                SettingsScreen()
            }
        }
    }
}
