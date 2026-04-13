package net.dailyok.android.ui.theme

import androidx.compose.ui.unit.dp

/**
 * Daily OK elevation tokens used for cards, sheets, and floating surfaces.
 *
 * These values pair with Material 3 tonal elevation and provide a consistent
 * depth ramp across the app. Use these instead of raw dp values so that the
 * overall depth language stays consistent as the design evolves.
 */
object DailyOKElevation {
    /** Flush with the background — backgrounds, list rows. */
    val level0 = 0.dp

    /** Subtle — resting cards, list items with separation. */
    val level1 = 1.dp

    /** Standard — raised cards (weekly summary, receiver status). */
    val level2 = 3.dp

    /** Prominent — hero / gradient cards, selected items. */
    val level3 = 6.dp

    /** Floating — FABs, bottom nav container, snackbars. */
    val level4 = 8.dp

    /** Highest — modal sheets and dialogs. */
    val level5 = 12.dp
}
