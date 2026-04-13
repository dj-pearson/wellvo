package net.dailyok.android.util

import android.util.Log
import net.dailyok.android.BuildConfig

/**
 * Debug-only logging utility. All log calls are no-ops in release builds,
 * preventing sensitive operational data from appearing in production logcat.
 */
object DebugLog {
    fun d(tag: String, message: String) {
        if (BuildConfig.DEBUG) Log.d(tag, message)
    }

    fun w(tag: String, message: String) {
        if (BuildConfig.DEBUG) Log.w(tag, message)
    }

    fun w(tag: String, message: String, throwable: Throwable) {
        if (BuildConfig.DEBUG) Log.w(tag, message, throwable)
    }

    fun e(tag: String, message: String) {
        if (BuildConfig.DEBUG) Log.e(tag, message)
    }

    fun e(tag: String, message: String, throwable: Throwable) {
        if (BuildConfig.DEBUG) Log.e(tag, message, throwable)
    }

    fun i(tag: String, message: String) {
        if (BuildConfig.DEBUG) Log.i(tag, message)
    }
}
