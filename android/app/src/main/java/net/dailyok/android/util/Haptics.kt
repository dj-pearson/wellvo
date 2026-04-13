package net.dailyok.android.util

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * Semantic haptic feedback API for DailyOK.
 *
 * Callers use meaningful verbs (checkInSuccess, actionConfirm, warning, error…)
 * instead of raw HapticFeedback constants so that the tactile language stays
 * consistent across the entire app.
 *
 * Honors the system "touch feedback" / accessibility settings automatically
 * because Android routes [performHapticFeedback] through those toggles.
 */
object DailyOKHaptics {

    /** Light tick — use for selection changes (picking a mood, a location tag). */
    fun selection(view: View) {
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }

    /** Single confirm tap — buttons, toggles. */
    fun confirm(view: View) {
        view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
    }

    /** Success pattern — successful check-in, pairing complete. */
    fun checkInSuccess(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            vibrate(context, VibrationEffect.createPredefined(VibrationEffect.EFFECT_DOUBLE_CLICK))
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrate(
                context,
                VibrationEffect.createWaveform(longArrayOf(0, 30, 80, 30), -1)
            )
        }
    }

    /** Warning pattern — escalation warning, low battery hint. */
    fun warning(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            vibrate(context, VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK))
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrate(context, VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE))
        }
    }

    /** Error pattern — failed check-in, auth failure, network error. */
    fun error(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrate(
                context,
                VibrationEffect.createWaveform(longArrayOf(0, 50, 80, 50, 80, 50), -1)
            )
        }
    }

    private fun vibrate(context: Context, effect: VibrationEffect) {
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vibrator?.hasVibrator() == true) {
            vibrator.vibrate(effect)
        }
    }
}
