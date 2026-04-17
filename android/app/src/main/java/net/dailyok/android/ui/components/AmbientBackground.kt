package net.dailyok.android.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import kotlin.math.cos
import kotlin.math.sin
import net.dailyok.android.ui.theme.DailyOKGreen100
import net.dailyok.android.ui.theme.DailyOKGreen200
import net.dailyok.android.ui.theme.DailyOKGreen300
import net.dailyok.android.ui.theme.DailyOKGreen900
import net.dailyok.android.ui.theme.DailyOKGold
import net.dailyok.android.ui.theme.DailyOKGoldLight
import net.dailyok.android.ui.theme.DailyOKIndigo
import net.dailyok.android.ui.theme.DailyOKTeal
import net.dailyok.android.ui.theme.ErrorRed
import net.dailyok.android.ui.theme.WarningOrange

/**
 * Ambient, slowly-drifting gradient backdrop used behind glass surfaces.
 *
 * Renders three soft blurred "orbs" in brand-consistent colors that gently
 * drift, giving the app a living, premium feel without distracting from content.
 */
enum class AmbientTone { Calm, Warm, Alert, Neutral }

@Composable
fun AmbientBackground(
    tone: AmbientTone = AmbientTone.Calm,
    modifier: Modifier = Modifier
) {
    val bg = MaterialTheme.colorScheme.background
    val isDark = (bg.red + bg.green + bg.blue) / 3f < 0.5f

    val base = when {
        isDark -> bg
        tone == AmbientTone.Calm -> Color(0xFFF0FDF4)
        tone == AmbientTone.Warm -> Color(0xFFFFFAED)
        tone == AmbientTone.Alert -> Color(0xFFFDF2EF)
        else -> Color(0xFFF9FAFB)
    }

    val orbs = remember(tone, isDark) { orbsFor(tone, isDark) }

    val transition = rememberInfiniteTransition(label = "ambient")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = (Math.PI * 2).toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 18_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "phase"
    )

    Canvas(modifier = modifier.fillMaxSize().background(base)) {
        val w = size.width
        val h = size.height
        orbs.forEachIndexed { idx, orb ->
            val drift = 24f
            val cx = w * orb.x + sin(phase + idx) * drift
            val cy = h * orb.y + cos(phase + idx * 1.3f) * drift
            val radius = w * orb.size
            val brush = Brush.radialGradient(
                colors = listOf(
                    orb.color.copy(alpha = if (isDark) 0.5f else 0.65f),
                    Color.Transparent
                ),
                center = Offset(cx, cy),
                radius = radius
            )
            drawRect(brush = brush)
        }
    }
}

private data class Orb(val color: Color, val size: Float, val x: Float, val y: Float)

private fun orbsFor(tone: AmbientTone, isDark: Boolean): List<Orb> = when (tone) {
    AmbientTone.Calm -> listOf(
        Orb(DailyOKGreen300, 0.9f, -0.15f, -0.1f),
        Orb(DailyOKTeal.copy(alpha = 0.6f), 0.8f, 0.55f, 0.15f),
        Orb(if (isDark) DailyOKGreen900 else DailyOKGreen100, 1.1f, 0.1f, 0.7f)
    )
    AmbientTone.Warm -> listOf(
        Orb(DailyOKGoldLight, 0.95f, -0.1f, -0.05f),
        Orb(DailyOKGold.copy(alpha = 0.45f), 0.75f, 0.6f, 0.2f),
        Orb(DailyOKGreen200, 1.0f, 0.2f, 0.75f)
    )
    AmbientTone.Alert -> listOf(
        Orb(WarningOrange.copy(alpha = 0.45f), 0.85f, -0.1f, 0f),
        Orb(ErrorRed.copy(alpha = 0.3f), 0.75f, 0.55f, 0.25f),
        Orb(DailyOKGreen100, 0.95f, 0.15f, 0.75f)
    )
    AmbientTone.Neutral -> listOf(
        Orb(DailyOKIndigo.copy(alpha = 0.25f), 0.8f, -0.1f, -0.1f),
        Orb(DailyOKGreen200, 0.9f, 0.55f, 0.2f),
        Orb(DailyOKTeal.copy(alpha = 0.3f), 1.0f, 0.1f, 0.7f)
    )
}
