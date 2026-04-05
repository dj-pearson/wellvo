package net.wellvo.android.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private val LightColorScheme = lightColorScheme(
    primary = WellvoGreen500,
    onPrimary = White,
    primaryContainer = WellvoGreen100,
    onPrimaryContainer = WellvoGreen900,
    secondary = WellvoGreen600,
    onSecondary = White,
    tertiary = WellvoTeal,
    onTertiary = White,
    background = SurfaceLight,
    onBackground = Gray900,
    surface = SurfaceLight,
    onSurface = Gray900,
    surfaceVariant = SurfaceLightMed,
    onSurfaceVariant = Gray700,
    surfaceTint = WellvoGreen500,
    error = ErrorRed,
    onError = White,
    outline = Gray200,
    outlineVariant = SurfaceLightHigh,
)

private val DarkColorScheme = darkColorScheme(
    primary = WellvoGreen300,
    onPrimary = WellvoGreen900,
    primaryContainer = WellvoGreen800,
    onPrimaryContainer = WellvoGreen100,
    secondary = WellvoGreen400,
    onSecondary = WellvoGreen900,
    tertiary = WellvoTeal,
    onTertiary = White,
    background = SurfaceDark,
    onBackground = White,
    surface = SurfaceDark,
    onSurface = White,
    surfaceVariant = SurfaceDarkMed,
    onSurfaceVariant = Gray200,
    surfaceTint = WellvoGreen400,
    error = ErrorRed,
    onError = White,
    outline = Gray500,
    outlineVariant = SurfaceDarkHigh,
)

@Composable
fun WellvoTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        shapes = Shapes,
        content = content
    )
}
