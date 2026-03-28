package net.wellvo.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.wellvo.android.network.ApiService
import net.wellvo.android.network.WellvoError
import javax.inject.Inject
import kotlin.math.min
import kotlin.math.pow

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
    val isLockedOut: Boolean = false
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
                val response = apiService.redeemCode(code)

                if (response.error != null) {
                    val newAttempts = _uiState.value.failedAttempts + 1
                    if (newAttempts >= 10) {
                        lockoutEndTimeMs = System.currentTimeMillis() + 15 * 60 * 1000
                        _uiState.value = _uiState.value.copy(
                            isLoading = false,
                            failedAttempts = newAttempts,
                            isLockedOut = true,
                            errorMessage = "Too many failed attempts. Try again in 15 minutes."
                        )
                    } else {
                        _uiState.value = _uiState.value.copy(
                            isLoading = false,
                            failedAttempts = newAttempts,
                            errorMessage = "${response.error} (${10 - newAttempts} attempts remaining)"
                        )
                    }
                    return@launch
                }

                // Success — reset attempts
                if (response.alreadyMember == true || response.success == true) {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        success = true,
                        failedAttempts = 0,
                        familyName = response.name,
                        checkinTime = response.checkinTime,
                        familyId = response.familyId,
                        role = response.role
                    )
                } else {
                    val newAttempts = _uiState.value.failedAttempts + 1
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        failedAttempts = newAttempts,
                        errorMessage = "Invalid or expired pairing code. (${10 - newAttempts} attempts remaining)"
                    )
                }
            } catch (e: WellvoError) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = e.localizedMessage
                )
            }
        }
    }
}
