package net.dailyok.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import net.dailyok.android.ui.theme.SurfaceDarkHigh
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKGreen100
import net.dailyok.android.ui.theme.DailyOKGreen400
import net.dailyok.android.ui.theme.DailyOKGreen50
import net.dailyok.android.ui.theme.DailyOKGreen700
import net.dailyok.android.ui.theme.DailyOKGreen900
import net.dailyok.android.ui.theme.DailyOKSpacing

/**
 * A hero card with a soft brand gradient background. Use sparingly for the
 * highest-priority information on a screen (weekly summary, streak highlight,
 * premium-feature teasers).
 */
@Composable
fun GradientHeroCard(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    trailingIcon: ImageVector? = null,
    trailingIconDescription: String? = null,
    content: @Composable (() -> Unit)? = null,
) {
    val isDark = isSystemInDarkTheme()
    val gradient = if (isDark) {
        Brush.linearGradient(
            colors = listOf(DailyOKGreen900, SurfaceDarkHigh),
        )
    } else {
        Brush.linearGradient(
            colors = listOf(DailyOKGreen50, DailyOKGreen100),
        )
    }
    val titleColor = if (isDark) Color.White else DailyOKGreen900
    val subtitleColor = if (isDark) DailyOKGreen100 else DailyOKGreen700
    val iconTint = if (isDark) DailyOKGreen400 else DailyOKGreen700

    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.Transparent),
        elevation = CardDefaults.cardElevation(defaultElevation = DailyOKElevation.level3),
        shape = MaterialTheme.shapes.large,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(MaterialTheme.shapes.large)
                .background(gradient)
                .padding(DailyOKSpacing.xl),
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = title,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = titleColor,
                        )
                        if (subtitle != null) {
                            Spacer(Modifier.height(DailyOKSpacing.xxs))
                            Text(
                                text = subtitle,
                                style = MaterialTheme.typography.bodyMedium,
                                color = subtitleColor,
                            )
                        }
                    }
                    if (trailingIcon != null) {
                        Spacer(Modifier.width(DailyOKSpacing.sm))
                        Icon(
                            imageVector = trailingIcon,
                            contentDescription = trailingIconDescription,
                            tint = iconTint,
                            modifier = Modifier.size(32.dp),
                        )
                    }
                }
                if (content != null) {
                    Spacer(Modifier.height(DailyOKSpacing.md))
                    content()
                }
            }
        }
    }
}

/**
 * A small stat card showing a prominent value, a descriptive label, and an
 * optional delta indicator. Designed to tile 2-3 across on a dashboard row.
 */
@Composable
fun PremiumStatCard(
    value: String,
    label: String,
    modifier: Modifier = Modifier,
    accent: Color? = null,
    delta: StatDelta? = null,
    contentDescriptionOverride: String? = null,
) {
    val color = accent ?: MaterialTheme.colorScheme.primary
    val semanticsLabel = contentDescriptionOverride ?: "$label: $value"

    Card(
        modifier = modifier
            .semantics { contentDescription = semanticsLabel },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = DailyOKElevation.level1),
        shape = MaterialTheme.shapes.medium,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(DailyOKSpacing.md),
            verticalArrangement = Arrangement.spacedBy(DailyOKSpacing.xxs),
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = color,
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (delta != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = if (delta.positive) Icons.Default.ArrowUpward else Icons.Default.ArrowDownward,
                        contentDescription = null,
                        tint = if (delta.positive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(14.dp),
                    )
                    Spacer(Modifier.width(DailyOKSpacing.xxs))
                    Text(
                        text = delta.label,
                        style = MaterialTheme.typography.labelSmall,
                        color = if (delta.positive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                    )
                }
            }
        }
    }
}

data class StatDelta(val label: String, val positive: Boolean)
