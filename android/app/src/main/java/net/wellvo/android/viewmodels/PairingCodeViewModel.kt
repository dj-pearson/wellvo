package net.wellvo.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.wellvo.android.network.ApiService
import net.wellvo.android.network.WellvoError
import javax.inject.Inject

data class PairingCodeUiState(
    val code: String = "",
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val success: Boolean = false,
    val familyName: String? = null,
    val checkinTime: String? = null,
    val familyId: String? = null,
    val role: String? = null
)

@HiltViewModel
class PairingCodeViewModel @Inject constructor(
    private val apiService: ApiService
) : ViewModel() {

    private val _uiState = MutableStateFlow(PairingCodeUiState())
    val uiState: StateFlow<PairingCodeUiState> = _uiState.asStateFlow()

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

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                val response = apiService.redeemCode(code)

                if (response.error != null) {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        errorMessage = response.error
                    )
                    return@launch
                }

                if (response.alreadyMember == true) {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        success = true,
                        familyName = response.name,
                        checkinTime = response.checkinTime,
                        familyId = response.familyId,
                        role = response.role
                    )
                    return@launch
                }

                if (response.success == true) {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        success = true,
                        familyName = response.name,
                        checkinTime = response.checkinTime,
                        familyId = response.familyId,
                        role = response.role
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        errorMessage = "Invalid or expired pairing code."
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
