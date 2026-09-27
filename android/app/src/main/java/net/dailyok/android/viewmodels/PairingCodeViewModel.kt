package net.dailyok.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.dailyok.android.network.ApiService
import net.dailyok.android.network.DailyOKError
import net.dailyok.android.network.JoinPreviewOutcome
import net.dailyok.android.network.JoinPreviews
import androidx.compose.runtime.Immutable
import javax.inject.Inject
import kotlin.math.min
import kotlin.math.pow

@Immutable
data class PairingCodeUiState(
    val code: String = "",
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val success: Boolean = false,
    val familyName: String? = null,
    val checkinTime: String? = null,
    val familyId: String? = null,
    val role: String? = null,
    val failedAttempts: Int = 0,
    val isLockedOut: Boolean = false,
    /** The family behind the code, waiting for "Join". Nothing is joined yet. */
    val consent: net.dailyok.android.network.JoinPreview? = null
)

@HiltViewModel
class PairingCodeViewModel @Inject constructor(
    private val apiService: ApiService
) : ViewModel() {

    private val _uiState = MutableStateFlow(PairingCodeUiState())
    val uiState: StateFlow<PairingCodeUiState> = _uiState.asStateFlow()

    private var lockoutEndTimeMs: Long = 0

    fun updateCode(code: String) {
        if (code.length <= 6 && code.all { it.isDigit() }) {
            _uiState.value = _uiState.value.copy(code = code, errorMessage = null)
        }
    }

    fun redeemPairingCode() {
        val code = _uiState.value.code
        if (code.length != 6) {
            _uiState.value = _uiState.value.copy(errorMessage = "Please enter a 6-digit pairing code.")
            return
        }

        // Check lockout
        if (_uiState.value.isLockedOut && System.currentTimeMillis() < lockoutEndTimeMs) {
            val remainingMin = ((lockoutEndTimeMs - System.currentTimeMillis()) / 60000) + 1
            _uiState.value = _uiState.value.copy(
                errorMessage = "Too many failed attempts. Try again in $remainingMin minute${if (remainingMin == 1L) "" else "s"}."
            )
            return
        } else if (_uiState.value.isLockedOut) {
            // Lockout expired, reset
            _uiState.value = _uiState.value.copy(isLockedOut = false, failedAttempts = 0)
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)

            // Exponential backoff delay between attempts
            val attempts = _uiState.value.failedAttempts
            if (attempts > 0) {
                val delayMs = min(2.0.pow(attempts - 1).toLong() * 1000, 16000)
                delay(delayMs)
            }

            try {
                // Ask first (redeem-code `preview`, edge pass 6): show whose
                // family this is, and as what, before joining it.
                when (val outcome = JoinPreviews.interpret(apiService.previewCode(code))) {
                    is JoinPreviewOutcome.AskFirst -> {
                        _uiState.value = _uiState.value.copy(
                            isLoading = false,
                            failedAttempts = 0,
                            consent = outcome.preview
                        )
                        return@launch
                    }
                    is JoinPreviewOutcome.AlreadyJoined -> {
                        // Already in this family, or a server without
                        // `preview` that joined at once: nothing to ask.
                        _uiState.value = _uiState.value.copy(
                            isLoading = false,
                            success = true,
                            failedAttempts = 0,
                            familyId = outcome.familyId,
                            role = outcome.role
                        )
                        return@launch
                    }
                    is JoinPreviewOutcome.NoInvite -> {
                        // Never join without having shown the family.
                        _uiState.value = _uiState.value.copy(
                            isLoading = false,
                            errorMessage = "Invalid or expired code. Please check and try again."
                        )
                        return@launch
                    }
                }
            } catch (e: DailyOKError) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = e.localizedMessage
                )
            }
        }
    }

    /** "Join" on the consent card: redeem the code for real. */
    fun confirmJoin() {
        val code = _uiState.value.code
        val preview = _uiState.value.consent ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                val response = apiService.redeemCode(code)
                if (response.success == true || response.alreadyMember == true) {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        success = true,
                        consent = null,
                        familyName = response.name ?: preview.presentableOwner?.let { "$it's family" },
                        checkinTime = response.checkinTime,
                        familyId = response.familyId,
                        role = response.role
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        consent = null,
                        errorMessage = response.error ?: "Couldn't join with this code. Please try again."
                    )
                }
            } catch (e: DailyOKError) {
                // e.g. the code was used or expired in the meantime, or the
                // family is full: back to the code entry with the reason.
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    consent = null,
                    errorMessage = e.localizedMessage
                )
            }
        }
    }

    /** "Not now": nothing was joined; back to the code entry. */
    fun declineJoin() {
        _uiState.value = _uiState.value.copy(consent = null, code = "", errorMessage = null)
    }
}
