package com.uuvpn.pro.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val DarkColorScheme = darkColorScheme(
    primary = Primary,
    onPrimary = TextOnPrimary,
    primaryContainer = PrimaryDark,
    onPrimaryContainer = TextPrimary,

    secondary = PrimaryVariant,
    onSecondary = TextOnPrimary,
    secondaryContainer = SurfaceCardLight,
    onSecondaryContainer = TextPrimary,

    tertiary = Info,
    onTertiary = TextOnPrimary,

    background = Surface,
    onBackground = TextPrimary,

    surface = Surface,
    onSurface = TextPrimary,
    surfaceVariant = SurfaceCard,
    onSurfaceVariant = TextSecondary,

    error = Error,
    onError = TextPrimary,
    errorContainer = Error.copy(alpha = 0.2f),
    onErrorContainer = Error,

    outline = SurfaceBorder,
    outlineVariant = SurfaceBorder.copy(alpha = 0.5f),

    inverseSurface = TextPrimary,
    inverseOnSurface = Surface,
    inversePrimary = PrimaryDark,

    surfaceTint = Primary,
)

@Composable
fun UuVpnTheme(
    content: @Composable () -> Unit
) {
    val colorScheme = DarkColorScheme

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = Color.Transparent.toArgb()
            window.navigationBarColor = Surface.toArgb()
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = false
                isAppearanceLightNavigationBars = false
            }
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        shapes = AppShapes,
        content = content,
    )
}
