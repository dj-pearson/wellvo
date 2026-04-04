package net.wellvo.android.ui.theme

import androidx.compose.ui.unit.dp

/**
 * Consistent spacing tokens used across the Wellvo app.
 * Follows a 4dp base grid for visual consistency.
 */
object WellvoSpacing {
    /** 4.dp — Tight spacing for inline elements */
    val xxs = 4.dp
    /** 8.dp — Default spacing between related items */
    val xs = 8.dp
    /** 12.dp — Spacing between closely related groups */
    val sm = 12.dp
    /** 16.dp — Standard content padding and section spacing */
    val md = 16.dp
    /** 20.dp — Medium-large spacing */
    val lg = 20.dp
    /** 24.dp — Section separators, card padding */
    val xl = 24.dp
    /** 32.dp — Large section gaps */
    val xxl = 32.dp
    /** 48.dp — Extra large spacing for empty states, hero areas */
    val xxxl = 48.dp
}

/**
 * Standard icon sizes used across the app.
 */
object WellvoIconSize {
    val small = 16.dp
    val medium = 24.dp
    val large = 32.dp
    val xlarge = 48.dp
    val hero = 64.dp
}

/**
 * Standard component sizes.
 */
object WellvoSize {
    /** Minimum touch target per Material guidelines */
    val minTouchTarget = 48.dp
    val buttonHeight = 48.dp
    val chipHeight = 36.dp
    val avatarSmall = 32.dp
    val avatarMedium = 40.dp
    val avatarLarge = 56.dp
}
