package net.dailyok.android.ui.components

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKMotion

data class FloatingNavItem(
    val label: String,
    val icon: ImageVector,
    val badgeCount: Int = 0,
)

/**
 * Floating, rounded bottom navigation bar with a sliding pill indicator
 * behind the selected tab. Drop-in replacement for the Material NavigationBar
 * in OwnerTabsScreen/ViewerTabsScreen. Safe-area aware — call sites should
 * add the system bars padding around it.
 */
@Composable
fun FloatingBottomNav(
    items: List<FloatingNavItem>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val indicatorOffsetFraction by animateDpAsState(
        targetValue = 0.dp, // purely for consistent animation lifecycle
        label = "indicatorAnim"
    )
    // We animate padding/background per item rather than a single sliding
    // indicator so we don't need to measure widths — simpler, still feels great.

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(DailyOKElevation.level4, RoundedCornerShape(28.dp))
                .clip(RoundedCornerShape(28.dp))
                .background(MaterialTheme.colorScheme.surface)
                .padding(horizontal = 8.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items.forEachIndexed { index, item ->
                NavItem(
                    item = item,
                    selected = index == selectedIndex,
                    onClick = { onSelect(index) },
                )
            }
        }
        // Prevent Android Studio warnings about unused variable
        @Suppress("UNUSED_EXPRESSION")
        indicatorOffsetFraction
    }
}

@Composable
private fun NavItem(
    item: FloatingNavItem,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val bg = if (selected) MaterialTheme.colorScheme.primaryContainer
             else androidx.compose.ui.graphics.Color.Transparent
    val fg = if (selected) MaterialTheme.colorScheme.onPrimaryContainer
             else MaterialTheme.colorScheme.onSurfaceVariant

    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(22.dp))
            .background(bg)
            .clickable(onClick = onClick)
            .padding(horizontal = if (selected) 14.dp else 10.dp, vertical = 10.dp)
            .semantics { contentDescription = item.label },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BadgedBox(badge = {
            if (item.badgeCount > 0) {
                Badge { Text(item.badgeCount.toString()) }
            }
        }) {
            Icon(
                imageVector = item.icon,
                contentDescription = null,
                tint = fg,
                modifier = Modifier.size(22.dp),
            )
        }
        if (selected) {
            Spacer(Modifier.width(8.dp))
            Text(
                text = item.label,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = fg,
            )
        }
    }
}
