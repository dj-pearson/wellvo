package net.dailyok.android.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Daily OK glassmorphism tokens.
 *
 * Compose on Android 12+ supports `Modifier.blur` for true backdrop blur, but
 * to stay compatible with API 26 minimum we use layered, translucent surfaces
 * with hairline strokes and a gentle brand tint. Pair with [glassSurface] for
 * cards, sheets, floating nav, and overlays.
 */
object DailyOKGlass {
    val RadiusSmall: Dp = 14.dp
    val RadiusMedium: Dp = 20.dp
    val RadiusLarge: Dp = 28.dp
    val RadiusXL: Dp = 36.dp

    /** Hairline stroke used to catch ambient light on glass edges. */
    val StrokeLight: Color = Color.White.copy(alpha = 0.55f)
    val StrokeDark: Color = Color.White.copy(alpha = 0.14f)

    /** Subtle brand tints layered over translucent surfaces. */
    val TintLight: Color = DailyOKGreen50.copy(alpha = 0.55f)
    val TintDark: Color = DailyOKGreen900.copy(alpha = 0.55f)
}

/** Glass depth variants — mirrors the iOS `DailyOKGlassStyle` enum. */
enum class DailyOKGlassStyle(val alphaLight: Float, val alphaDark: Float) {
    UltraThin(0.55f, 0.38f),   // toolbars, chips
    Thin(0.72f, 0.55f),        // cards, list rows
    Regular(0.82f, 0.68f),     // bottom sheets, modals
    Thick(0.92f, 0.82f)        // paywall, overlays
}

/**
 * Apply a branded glass surface: translucent fill + subtle tint + hairline stroke + shadow.
 *
 * On Android 12+ consumers can chain [Modifier.blur] on the background layer for
 * a true frosted effect; this modifier intentionally stays compatible with older
 * APIs by leaning on layered translucency.
 */
@Composable
fun Modifier.glassSurface(
    style: DailyOKGlassStyle = DailyOKGlassStyle.Regular,
    shape: Shape = RoundedCornerShape(DailyOKGlass.RadiusLarge),
    elevation: Dp = DailyOKElevation.level3,
    isDark: Boolean = MaterialTheme.colorScheme.surface.luminance() < 0.5f
): Modifier {
    val surface = MaterialTheme.colorScheme.surface
    val alpha = if (isDark) style.alphaDark else style.alphaLight
    val tint = if (isDark) DailyOKGlass.TintDark else DailyOKGlass.TintLight
    val stroke = if (isDark) DailyOKGlass.StrokeDark else DailyOKGlass.StrokeLight

    val fill = Brush.verticalGradient(
        listOf(
            surface.copy(alpha = alpha).compositeOver(tint),
            surface.copy(alpha = (alpha - 0.08f).coerceAtLeast(0.25f))
        )
    )

    return this
        .shadow(elevation = elevation, shape = shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.25f))
        .clip(shape)
        .background(fill, shape)
        .border(width = 0.75.dp, color = stroke, shape = shape)
}

/** Approximate luminance for deciding light vs dark glass treatment. */
internal fun Color.luminance(): Float {
    return 0.2126f * red + 0.7152f * green + 0.0722f * blue
}

/** Lightweight over-compositing to keep tint subtle without an extra layer. */
internal fun Color.compositeOver(other: Color): Color {
    val outA = alpha + other.alpha * (1f - alpha)
    if (outA == 0f) return Color.Transparent
    val outR = (red * alpha + other.red * other.alpha * (1f - alpha)) / outA
    val outG = (green * alpha + other.green * other.alpha * (1f - alpha)) / outA
    val outB = (blue * alpha + other.blue * other.alpha * (1f - alpha)) / outA
    return Color(outR, outG, outB, outA)
}
