package net.wellvo.android.ui.components

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
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
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import net.wellvo.android.ui.theme.WellvoElevation
import net.wellvo.android.ui.theme.WellvoGold
import net.wellvo.android.ui.theme.WellvoGoldLight
import net.wellvo.android.ui.theme.WellvoGreen50
import net.wellvo.android.ui.theme.WellvoGreen100
import net.wellvo.android.ui.theme.WellvoGreen700
import net.wellvo.android.ui.theme.WellvoSpacing

data class PaywallFeature(
    val icon: ImageVector,
    val title: String,
    val description: String,
)

data class Testimonial(
    val quote: String,
    val author: String,
)

/**
 * Horizontal carousel showcasing premium features with animated page dots.
 * Designed to be embedded inside a paywall screen — parent provides the
 * feature list, testimonials list, and the CTA button at the bottom.
 */
@Composable
fun PaywallFeatureCarousel(
    features: List<PaywallFeature>,
    modifier: Modifier = Modifier,
) {
    val pagerState = rememberPagerState(pageCount = { features.size })

    Column(modifier = modifier.fillMaxWidth()) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxWidth(),
            pageSpacing = WellvoSpacing.md,
        ) { page ->
            PaywallFeatureCard(features[page])
        }

        Spacer(Modifier.height(WellvoSpacing.md))

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = WellvoSpacing.md),
            horizontalArrangement = Arrangement.Center,
        ) {
            repeat(features.size) { i ->
                val width by animateDpAsState(
                    targetValue = if (i == pagerState.currentPage) 24.dp else 8.dp,
                    label = "paywall-dot-$i"
                )
                Box(
                    modifier = Modifier
                        .padding(horizontal = 4.dp)
                        .height(8.dp)
                        .width(width)
                        .clip(RoundedCornerShape(4.dp))
                        .background(
                            if (i == pagerState.currentPage)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.surfaceVariant
                        )
                )
            }
        }
    }
}

@Composable
private fun PaywallFeatureCard(feature: PaywallFeature) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = WellvoSpacing.md)
            .clip(RoundedCornerShape(20.dp))
            .background(
                Brush.verticalGradient(
                    colors = listOf(WellvoGreen50, WellvoGreen100)
                )
            )
            .padding(WellvoSpacing.xl),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(Color.White),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = feature.icon,
                    contentDescription = null,
                    tint = WellvoGreen700,
                    modifier = Modifier.size(40.dp),
                )
            }
            Spacer(Modifier.height(WellvoSpacing.md))
            Text(
                text = feature.title,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                color = WellvoGreen700,
            )
            Spacer(Modifier.height(WellvoSpacing.xs))
            Text(
                text = feature.description,
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Animated "Save X%" badge for the annual plan.
 */
@Composable
fun AnnualSavingsBadge(
    percentSaved: Int,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(WellvoGoldLight)
            .padding(horizontal = WellvoSpacing.sm, vertical = 6.dp),
    ) {
        Text(
            text = "Save $percentSaved%",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = WellvoGold,
        )
    }
}

/**
 * A compact testimonial card for social proof.
 */
@Composable
fun TestimonialCard(
    testimonial: Testimonial,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(WellvoSpacing.md),
    ) {
        Column {
            Text(
                text = "\u201C${testimonial.quote}\u201D",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(WellvoSpacing.xs))
            Text(
                text = "— ${testimonial.author}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
