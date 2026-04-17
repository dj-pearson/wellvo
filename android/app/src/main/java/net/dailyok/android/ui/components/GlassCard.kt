package net.dailyok.android.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKGlass
import net.dailyok.android.ui.theme.DailyOKGlassStyle
import net.dailyok.android.ui.theme.glassSurface

/**
 * Reusable frosted-glass card container.
 *
 * Wrap any screen section in [GlassCard] to get a brand-consistent translucent
 * surface with a subtle brand tint, hairline stroke, and ambient shadow.
 */
@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    style: DailyOKGlassStyle = DailyOKGlassStyle.Regular,
    shape: Shape = RoundedCornerShape(DailyOKGlass.RadiusLarge),
    elevation: Dp = DailyOKElevation.level3,
    contentPadding: PaddingValues = PaddingValues(16.dp),
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .glassSurface(style = style, shape = shape, elevation = elevation)
            .padding(contentPadding)
    ) {
        content()
    }
}
