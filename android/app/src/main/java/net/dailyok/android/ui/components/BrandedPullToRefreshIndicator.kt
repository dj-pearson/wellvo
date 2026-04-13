package net.dailyok.android.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.unit.dp
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKGreen500

/**
 * Branded pull-to-refresh indicator. Shows a pulsing brand-green circle
 * with a rotating progress ring while refreshing; tracks the pull distance
 * before the refresh kicks in.
 *
 * Use inside [PullToRefreshBox] via the `indicator` slot:
 * ```
 * PullToRefreshBox(
 *     isRefreshing = refreshing,
 *     onRefresh = { ... },
 *     state = state,
 *     indicator = { BrandedPullToRefreshIndicator(state, refreshing) }
 * ) { ... }
 * ```
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrandedPullToRefreshIndicator(
    state: PullToRefreshState,
    isRefreshing: Boolean,
    modifier: Modifier = Modifier,
) {
    val pulse = rememberInfiniteTransition(label = "pull-to-refresh-pulse")
    val pulseScale by pulse.animateFloat(
        initialValue = 0.92f,
        targetValue = 1.08f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 900, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseScale"
    )

    val distance = state.distanceFraction.coerceIn(0f, 1f)

    Box(
        modifier = modifier
            .size(48.dp)
            .scale(if (isRefreshing) pulseScale else 0.5f + distance * 0.8f)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surface),
        contentAlignment = Alignment.Center,
    ) {
        if (isRefreshing) {
            CircularProgressIndicator(
                color = DailyOKGreen500,
                strokeWidth = 3.dp,
                modifier = Modifier.size(28.dp)
            )
        } else {
            // Resting state: solid brand dot that scales with pull distance.
            Box(
                modifier = Modifier
                    .size(20.dp)
                    .rotate(distance * 360f)
                    .clip(CircleShape)
                    .background(DailyOKGreen500)
            )
        }
    }
}
