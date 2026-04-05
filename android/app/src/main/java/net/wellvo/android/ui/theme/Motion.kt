package net.wellvo.android.ui.theme

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring

/**
 * Wellvo motion design tokens.
 *
 * Mirrors the Material 3 motion spec with Wellvo-specific naming so that
 * durations and easings stay consistent across every animation in the app.
 * Use these tokens instead of inline values to keep the app's feel unified.
 */
object WellvoMotion {
    // Durations (ms)
    const val DurationInstant = 50
    const val DurationShort = 150
    const val DurationMedium = 250
    const val DurationLong = 400
    const val DurationExtraLong = 600

    // Easings
    /** For general-purpose transitions that begin and end at rest. */
    val EasingStandard: Easing = CubicBezierEasing(0.2f, 0.0f, 0.0f, 1.0f)

    /** For elements that begin at rest and exit offscreen (deceleration). */
    val EasingEmphasizedDecelerate: Easing = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1.0f)

    /** For attention-grabbing transitions with a slight overshoot. */
    val EasingEmphasizedAccelerate: Easing = CubicBezierEasing(0.3f, 0.0f, 0.8f, 0.15f)

    /** Linear curve — use sparingly for shimmer / progress loops. */
    val EasingLinear: Easing = CubicBezierEasing(0f, 0f, 1f, 1f)

    // Spring specs for touch-driven components (check-in button, cards)
    fun <T> bouncySpring() = spring<T>(
        dampingRatio = Spring.DampingRatioMediumBouncy,
        stiffness = Spring.StiffnessMediumLow
    )

    fun <T> smoothSpring() = spring<T>(
        dampingRatio = Spring.DampingRatioNoBouncy,
        stiffness = Spring.StiffnessMedium
    )
}
