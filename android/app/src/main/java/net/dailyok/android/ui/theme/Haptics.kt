package net.dailyok.android.ui.theme

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView

/**
 * CompositionLocal-backed preference for non-essential haptics. The root of
 * the UI tree should `CompositionLocalProvider(LocalDailyOKHapticsEnabled provides ...)`
 * with the value read from SecureStorage so every call to [rememberDailyOKHaptics]
 * respects the user's preference without each screen needing to plumb it manually.
 */
val LocalDailyOKHapticsEnabled = compositionLocalOf { true }

/**
 * Daily OK haptic vocabulary mirroring the iOS counterpart.
 *
 * Prefer these semantic calls over raw `HapticFeedback` so every corner of
 * the app speaks the same tactile language.
 *
 * Usage:
 * ```kotlin
 * val haptics = rememberDailyOKHaptics()
 * haptics.success()
 * ```
 */
class DailyOKHaptics internal constructor(
    private val compose: HapticFeedback,
    private val view: View,
    private val nonEssentialEnabled: Boolean = true
) {
    fun selection() {
        if (!nonEssentialEnabled) return
        compose.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    }

    fun light() {
        if (!nonEssentialEnabled) return
        compose.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    }

    fun medium() {
        if (!nonEssentialEnabled) return
        compose.performHapticFeedback(HapticFeedbackType.LongPress)
    }

    /** Always fires regardless of the non-essential toggle — outcomes convey state. */
    fun success() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        } else {
            compose.performHapticFeedback(HapticFeedbackType.LongPress)
        }
    }

    /** Always fires regardless of the non-essential toggle. */
    fun warning() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            view.performHapticFeedback(HapticFeedbackConstants.GESTURE_THRESHOLD_ACTIVATE)
        } else {
            compose.performHapticFeedback(HapticFeedbackType.LongPress)
        }
    }

    /** Always fires regardless of the non-essential toggle. */
    fun error() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            view.performHapticFeedback(HapticFeedbackConstants.REJECT)
        } else {
            compose.performHapticFeedback(HapticFeedbackType.LongPress)
        }
    }
}

@Composable
fun rememberDailyOKHaptics(
    nonEssentialEnabled: Boolean = LocalDailyOKHapticsEnabled.current
): DailyOKHaptics {
    val compose = LocalHapticFeedback.current
    val view = LocalView.current
    return DailyOKHaptics(compose, view, nonEssentialEnabled)
}
