package net.dailyok.android.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.sin
import net.dailyok.android.ui.theme.DailyOKGold
import net.dailyok.android.ui.theme.DailyOKSpacing
import net.dailyok.android.util.ConsistencyBadge

private val StreakMilestones = setOf(7, 14, 30, 60, 100, 180, 365)

/**
 * A compact chip showing a flame + streak count. Only renders at streak >= 2.
 *
 * At milestone thresholds (7, 14, 30, 60, 100, 180, 365) the chip lights up
 * with a brand gradient fill + three orbiting sparkles that loop while the
 * milestone is held.
 */
@Composable
fun StreakChip(
    streakDays: Int,
    modifier: Modifier = Modifier,
) {
    if (streakDays < 2) return
    val isMilestone = streakDays in StreakMilestones
    val label = if (isMilestone) "Milestone: $streakDays day streak"
                else "$streakDays day streak"

    if (isMilestone) {
        MilestoneStreakChip(streakDays = streakDays, label = label, modifier = modifier)
    } else {
        StandardStreakChip(streakDays = streakDays, label = label, modifier = modifier)
    }
}

@Composable
private fun StandardStreakChip(
    streakDays: Int,
    label: String,
    modifier: Modifier,
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFFFFF1DB))
            .padding(horizontal = DailyOKSpacing.xs, vertical = 4.dp)
            .semantics { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.LocalFireDepartment,
            contentDescription = null,
            tint = Color(0xFFF97316),
            modifier = Modifier.size(14.dp),
        )
        Spacer(Modifier.width(4.dp))
        Text(
            text = "$streakDays",
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = Color(0xFF9A3412),
        )
    }
}

@Composable
private fun MilestoneStreakChip(
    streakDays: Int,
    label: String,
    modifier: Modifier,
) {
    val transition = rememberInfiniteTransition(label = "streakSparkle")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = (Math.PI * 2).toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 2400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "phase"
    )

    val density = LocalDensity.current
    Box(
        modifier = modifier
            .shadow(
                elevation = 6.dp,
                shape = RoundedCornerShape(12.dp),
                ambientColor = DailyOKGold.copy(alpha = 0.5f),
                spotColor = DailyOKGold.copy(alpha = 0.5f)
            )
            .clip(RoundedCornerShape(12.dp))
            .background(
                Brush.linearGradient(
                    listOf(DailyOKGold, Color(0xFFF97316))
                )
            )
            .border(
                width = 0.75.dp,
                color = Color.White.copy(alpha = 0.5f),
                shape = RoundedCornerShape(12.dp)
            )
            .semantics { contentDescription = label }
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Default.LocalFireDepartment,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(14.dp),
            )
            Spacer(Modifier.width(4.dp))
            Text(
                text = "$streakDays",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
        }

        // Orbiting sparkles
        repeat(3) { index ->
            val angle = phase + index * ((2 * Math.PI) / 3).toFloat()
            val rxPx = with(density) { 26.dp.toPx() }
            val ryPx = with(density) { 12.dp.toPx() }
            Icon(
                imageVector = Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.85f),
                modifier = Modifier
                    .align(Alignment.Center)
                    .offset(
                        x = with(density) { (cos(angle) * rxPx).toDp() },
                        y = with(density) { (sin(angle) * ryPx).toDp() }
                    )
                    .size(8.dp)
            )
        }
    }
}

/**
 * A tiny medal chip denoting the week's consistency tier.
 * Returns nothing for [ConsistencyBadge.None].
 */
@Composable
fun ConsistencyChip(
    badge: ConsistencyBadge,
    modifier: Modifier = Modifier,
) {
    if (badge == ConsistencyBadge.None) return
    val (bg, fg, label) = when (badge) {
        ConsistencyBadge.Gold -> Triple(Color(0xFFFEF3C7), DailyOKGold, "Gold")
        ConsistencyBadge.Silver -> Triple(Color(0xFFE5E7EB), Color(0xFF6B7280), "Silver")
        ConsistencyBadge.Bronze -> Triple(Color(0xFFFED7AA), Color(0xFFC2410C), "Bronze")
        ConsistencyBadge.None -> return
    }
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .padding(horizontal = DailyOKSpacing.xs, vertical = 4.dp)
            .semantics { contentDescription = "$label consistency badge" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.EmojiEvents,
            contentDescription = null,
            tint = fg,
            modifier = Modifier.size(14.dp),
        )
        Spacer(Modifier.width(4.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = fg,
        )
    }
}
