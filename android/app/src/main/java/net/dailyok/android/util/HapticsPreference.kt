package net.dailyok.android.util

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * App-wide preference for non-essential haptic feedback.
 *
 * Lives as a Hilt [Singleton] so the Settings screen (writer) and the root of
 * the Compose tree (reader) share the same live [StateFlow]. Value is persisted
 * via [SecureStorage] under [SecureStorage.Keys.HAPTICS_ENABLED].
 */
@Singleton
class HapticsPreference @Inject constructor(
    private val secureStorage: SecureStorage
) {
    private val _enabled = MutableStateFlow(
        secureStorage.loadBoolean(SecureStorage.Keys.HAPTICS_ENABLED, default = true)
    )
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    fun setEnabled(value: Boolean) {
        if (_enabled.value == value) return
        _enabled.value = value
        secureStorage.saveBoolean(SecureStorage.Keys.HAPTICS_ENABLED, value)
    }
}
