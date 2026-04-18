package net.dailyok.android.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import net.dailyok.android.ui.theme.rememberDailyOKHaptics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKGlassStyle
import net.dailyok.android.ui.theme.DailyOKGreen100
import net.dailyok.android.ui.theme.DailyOKGreen200
import net.dailyok.android.ui.theme.DailyOKGreen300
import net.dailyok.android.ui.theme.DailyOKGreen700
import net.dailyok.android.ui.theme.DailyOKMotion
import net.dailyok.android.ui.theme.glassSurface

data class FloatingNavItem(
    val label: String,
    val icon: ImageVector,
    val badgeCount: Int = 0,
)

/**
 * Floating, frosted-glass bottom navigation bar. The container uses the
 * branded `glassSurface` so the content behind shows through subtly, and the
 * selected tab morphs from a circle to a pill with a gradient fill.
 */
@Composable
fun FloatingBottomNav(
    items: List<FloatingNavItem>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptics = rememberDailyOKHaptics()

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .glassSurface(
                    style = DailyOKGlassStyle.Regular,
                    shape = RoundedCornerShape(32.dp),
                    elevation = DailyOKElevation.level4,
                )
                .padding(horizontal = 8.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items.forEachIndexed { index, item ->
                NavItem(
                    item = item,
                    selected = index == selectedIndex,
                    onClick = {
                        haptics.selection()
                        onSelect(index)
                    },
                )
            }
        }
    }
}

@Composable
private fun NavItem(
    item: FloatingNavItem,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val isDark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val fg = if (selected) {
        if (isDark) MaterialTheme.colorScheme.onPrimaryContainer else DailyOKGreen700
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    val pillBrush = Brush.linearGradient(
        listOf(
            DailyOKGreen100.copy(alpha = if (isDark) 0.35f else 1f),
            DailyOKGreen200.copy(alpha = if (isDark) 0.25f else 0.8f)
        )
    )
    val strokeColor = DailyOKGreen300.copy(alpha = 0.5f)

    val interaction = remember { MutableInteractionSource() }

    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(24.dp))
            .then(
                if (selected) {
                    Modifier
                        .background(pillBrush, RoundedCornerShape(24.dp))
                        .border(0.75.dp, strokeColor, RoundedCornerShape(24.dp))
                } else Modifier
            )
            .clickable(
                interactionSource = interaction,
                indication = null,
                onClick = onClick
            )
            .padding(horizontal = if (selected) 16.dp else 12.dp, vertical = 10.dp)
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
        AnimatedVisibility(
            visible = selected,
            enter = fadeIn(animationSpec = tween(DailyOKMotion.DurationShort)) +
                    expandHorizontally(animationSpec = tween(DailyOKMotion.DurationMedium)),
            exit = fadeOut(animationSpec = tween(DailyOKMotion.DurationShort)) +
                    shrinkHorizontally(animationSpec = tween(DailyOKMotion.DurationShort)),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
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
}

private fun Color.luminance(): Float =
    0.2126f * red + 0.7152f * green + 0.0722f * blue
