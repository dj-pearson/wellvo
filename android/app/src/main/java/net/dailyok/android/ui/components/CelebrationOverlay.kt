package net.dailyok.android.ui.components

import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import net.dailyok.android.ui.theme.DailyOKGreen400
import net.dailyok.android.ui.theme.DailyOKGreen500
import net.dailyok.android.ui.theme.DailyOKMotion

/**
 * A celebratory overlay that briefly shows a scale+fade checkmark with a
 * particle ring burst after a successful action (e.g. check-in).
 *
 * Usage: drive [visible] from the calling screen and set back to false in
 * [onComplete]. Respects system animator-duration-scale = 0 (reduced motion)
 * by showing only the static checkmark without the particle ring.
 */
@Composable
fun CelebrationOverlay(
    visible: Boolean,
    modifier: Modifier = Modifier,
    onComplete: () -> Unit,
) {
    val context = LocalContext.current
    val reduceMotion = remember {
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f
        ) == 0f
    }

    // Particle ring expansion (0f..1f). Only animated when motion is enabled.
    val ringProgress = remember { Animatable(0f) }

    LaunchedEffect(visible) {
        if (visible) {
            if (!reduceMotion) {
                ringProgress.snapTo(0f)
                ringProgress.animateTo(
                    targetValue = 1f,
                    animationSpec = tween(
                        durationMillis = DailyOKMotion.DurationExtraLong + 200,
                        easing = LinearOutSlowInEasing
                    )
                )
            }
            delay(400)
            onComplete()
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .semantics { contentDescription = "Success" },
        contentAlignment = Alignment.Center,
    ) {
        AnimatedVisibility(
            visible = visible,
            enter = fadeIn(tween(DailyOKMotion.DurationShort)) +
                    scaleIn(
                        initialScale = 0.4f,
                        animationSpec = tween(DailyOKMotion.DurationMedium)
                    ),
            exit = fadeOut(tween(DailyOKMotion.DurationShort)) +
                    scaleOut(targetScale = 1.2f),
        ) {
            Box(contentAlignment = Alignment.Center) {
                if (!reduceMotion) {
                    val progress = ringProgress.value
                    Canvas(modifier = Modifier.size(220.dp)) {
                        val maxRadius = size.minDimension / 2f
                        val radius = maxRadius * progress
                        val alpha = (1f - progress).coerceIn(0f, 1f)
                        drawCircle(
                            color = DailyOKGreen400.copy(alpha = alpha * 0.6f),
                            radius = radius,
                            style = androidx.compose.ui.graphics.drawscope.Stroke(width = 8f)
                        )
                        drawCircle(
                            color = DailyOKGreen400.copy(alpha = alpha * 0.3f),
                            radius = radius * 0.7f,
                            style = androidx.compose.ui.graphics.drawscope.Stroke(width = 4f)
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .size(96.dp)
                        .clip(CircleShape)
                        .background(DailyOKGreen500),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Default.Check,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(56.dp),
                    )
                }
            }
        }
    }
}
