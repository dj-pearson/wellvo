package net.dailyok.android.viewmodels

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import net.dailyok.android.util.HapticsPreference
import javax.inject.Inject

/**
 * Lightweight app-wide preferences VM used at the root of the compose tree so
 * CompositionLocals (e.g. haptic feedback toggle) can stay live without
 * forcing every screen's VM to inject the underlying preference repository.
 */
@HiltViewModel
class AppPreferencesViewModel @Inject constructor(
    private val hapticsPreference: HapticsPreference
) : ViewModel() {
    val hapticsEnabled: StateFlow<Boolean> = hapticsPreference.enabled
}
