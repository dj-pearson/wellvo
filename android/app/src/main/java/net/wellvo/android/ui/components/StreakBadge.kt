package net.wellvo.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import net.wellvo.android.ui.theme.WellvoGold
import net.wellvo.android.ui.theme.WellvoSpacing
import net.wellvo.android.util.ConsistencyBadge

/**
 * A compact chip showing a flame + streak count. Only renders at streak >= 2
 * (shorter streaks don't feel like streaks yet). Use next to a name on
 * ReceiverStatusCard or on the Receiver home header.
 */
@Composable
fun StreakChip(
    streakDays: Int,
    modifier: Modifier = Modifier,
) {
    if (streakDays < 2) return
    val label = "$streakDays day streak"
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFFFFF1DB))
            .padding(horizontal = WellvoSpacing.xs, vertical = 4.dp)
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
        ConsistencyBadge.Gold -> Triple(Color(0xFFFEF3C7), WellvoGold, "Gold")
        ConsistencyBadge.Silver -> Triple(Color(0xFFE5E7EB), Color(0xFF6B7280), "Silver")
        ConsistencyBadge.Bronze -> Triple(Color(0xFFFED7AA), Color(0xFFC2410C), "Bronze")
        ConsistencyBadge.None -> return
    }
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .padding(horizontal = WellvoSpacing.xs, vertical = 4.dp)
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
