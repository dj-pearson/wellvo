package net.wellvo.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.wellvo.android.data.models.FamilyMember
import net.wellvo.android.data.models.ReceiverSettings
import javax.inject.Inject

data class ReceiverOnboardingUiState(
    val currentStep: Int = 0,
    val receiverName: String = "",
    val checkinTime: String? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val notificationDenied: Boolean = false,
    val isComplete: Boolean = false
)

@HiltViewModel
class ReceiverOnboardingViewModel @Inject constructor(
    private val supabase: SupabaseClient
) : ViewModel() {

    private val _uiState = MutableStateFlow(ReceiverOnboardingUiState())
    val uiState: StateFlow<ReceiverOnboardingUiState> = _uiState.asStateFlow()

    fun loadReceiverSettings() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            try {
                val userId = supabase.auth.currentUserOrNull()?.id ?: return@launch

                val member = supabase.postgrest.from("family_members")
                    .select {
                        filter { eq("user_id", userId) }
                        filter { eq("role", "receiver") }
                    }
                    .decodeSingleOrNull<FamilyMember>()

                if (member != null) {
                    val settings = supabase.postgrest.from("receiver_settings")
                        .select {
                            filter { eq("family_member_id", member.id) }
                        }
                        .decodeSingleOrNull<ReceiverSettings>()

                    val user = supabase.postgrest.from("users")
                        .select {
                            filter { eq("id", userId) }
                        }
                        .decodeSingleOrNull<net.wellvo.android.data.models.AppUser>()

                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        receiverName = user?.displayName ?: "",
                        checkinTime = settings?.checkinTime?.let { formatTime(it) }
                    )
                } else {
                    _uiState.value = _uiState.value.copy(isLoading = false)
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = e.message
                )
            }
        }
    }

    fun acceptInvite(token: String) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                // The invite acceptance is handled server-side during auth/auto-join.
                // Load the receiver settings after accepting.
                loadReceiverSettings()
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = e.message
                )
            }
        }
    }

    fun advance() {
        val next = _uiState.value.currentStep + 1
        _uiState.value = _uiState.value.copy(currentStep = next, errorMessage = null)
    }

    fun onNotificationPermissionResult(granted: Boolean) {
        _uiState.value = _uiState.value.copy(notificationDenied = !granted)
        advance()
    }

    fun markComplete() {
        _uiState.value = _uiState.value.copy(isComplete = true)
    }

    private fun formatTime(time: String): String {
        // time is "HH:mm" format, convert to 12-hour display
        val parts = time.split(":")
        if (parts.size != 2) return time
        val hour = parts[0].toIntOrNull() ?: return time
        val minute = parts[1].toIntOrNull() ?: return time
        val amPm = if (hour < 12) "AM" else "PM"
        val displayHour = when {
            hour == 0 -> 12
            hour > 12 -> hour - 12
            else -> hour
        }
        return "%d:%02d %s".format(displayHour, minute, amPm)
    }
}
