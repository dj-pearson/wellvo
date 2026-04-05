package net.wellvo.android.util

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp

/**
 * Accessibility helpers for Wellvo Compose screens.
 *
 * The goal is to give every screen a small set of drop-in modifiers so that
 * consistent a11y behavior (content descriptions, live-region announcements,
 * font-scale-aware layouts) is easy to apply without reinventing the wheel.
 */
object A11y {

    /** Largest font scale we fully support in layouts — above this, callers
     *  should switch to a simpler single-column layout so content stays usable. */
    const val MAX_SUPPORTED_FONT_SCALE = 2.0f

    /**
     * Current system font scale. Read from [LocalConfiguration]. 1.0 = default,
     * 2.0 = "largest" accessibility text size on most devices.
     */
    @Composable
    @ReadOnlyComposable
    fun fontScale(): Float = LocalConfiguration.current.fontScale

    /** True if the user has set a font scale that requires compact layouts
     *  (e.g. stacking 3-across stat cards into a single column). */
    @Composable
    @ReadOnlyComposable
    fun useCompactLayoutForLargeText(): Boolean = fontScale() > 1.3f
}

/**
 * Add a content description to any composable. Prefer this over remembering
 * the verbose `.semantics { contentDescription = ... }` pattern everywhere.
 */
fun Modifier.describeAs(description: String): Modifier =
    this.semantics { contentDescription = description }

/**
 * Mark a composable as an assertive live region — screen readers will
 * announce the updated content automatically (e.g. "check-in successful",
 * "error retrying", offline banner text).
 */
fun Modifier.announceOnChange(): Modifier =
    this.semantics { liveRegion = LiveRegionMode.Polite }
