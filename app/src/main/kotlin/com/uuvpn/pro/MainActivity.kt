package com.uuvpn.pro

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.uuvpn.pro.ui.navigation.AppNavigation
import com.uuvpn.pro.ui.theme.UuVpnTheme
import dagger.hilt.android.AndroidEntryPoint

/**
 * Single Activity — Compose 导航承载
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            UuVpnTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = com.uuvpn.pro.ui.theme.Surface
                ) {
                    AppNavigation()
                }
            }
        }
    }
}
