package net.dailyok.android.viewmodels

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
import net.dailyok.android.data.models.FamilyMember
import net.dailyok.android.data.models.ReceiverSettings
import androidx.compose.runtime.Immutable
import javax.inject.Inject

@Immutable
data class ReceiverOnboardingUiState(
    val currentStep: Int = 0,
    val receiverName: String = "",
    val checkinTime: String? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val notificationDenied: Boolean = false,
    val isComplete: Boolean = false,
    /** The invite couldn't be redeemed; offer Try Again / Back, never "all set". */
    val joinFailed: Boolean = false,
    /** Who they joined, from the server ("Mom", "The Smiths"). */
    val ownerName: String? = null
)

@HiltViewModel
class ReceiverOnboardingViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val familyService: net.dailyok.android.services.FamilyService
) : ViewModel() {

    private var lastToken: String? = null

    private val _uiState = MutableStateFlow(ReceiverOnboardingUiState())
    val uiState: StateFlow<ReceiverOnboardingUiState> = _uiState.asStateFlow()

    fun loadReceiverSettings() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            try {
                val userId = supabase.auth.currentUserOrNull()?.id ?: return@launch

                // Active only, first row: a receiver who was removed and
                // re-invited has two rows, and decodeSingleOrNull threw on them.
                val member = supabase.postgrest.from("family_members")
                    .select {
                        filter { eq("user_id", userId) }
                        filter { eq("role", "receiver") }
                        filter { eq("status", "active") }
                        limit(1)
                    }
                    .decodeList<FamilyMember>()
                    .firstOrNull()

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
                        .decodeSingleOrNull<net.dailyok.android.data.models.AppUser>()

                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        receiverName = user?.displayName ?: "",
                        checkinTime = _uiState.value.checkinTime
                            ?: settings?.checkinTime?.let { formatTime(it) }
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

    /**
     * Redeem the invite link's token. This used to only reload settings — it
     * never called the server — so a receiver who arrived by link was shown
     * "all set" for a family they had not joined.
     */
    fun acceptInvite(token: String) {
        lastToken = token
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null, joinFailed = false)
            try {
                val joined = familyService.acceptInvite(token)
                _uiState.value = _uiState.value.copy(
                    checkinTime = joined.checkinTime?.let { formatTime(it) },
                    ownerName = joined.ownerName?.takeIf { it.isNotBlank() && it != "User" }
                )
                loadReceiverSettings()
            } catch (e: net.dailyok.android.network.DailyOKError.Rejected) {
                if (e.status == 409) {
                    // "Already a member of this family" — the link tapped twice.
                    loadReceiverSettings()
                } else {
                    _uiState.value = _uiState.value.copy(isLoading = false, joinFailed = true, errorMessage = e.message)
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    joinFailed = true,
                    errorMessage = e.message ?: "Couldn't join. Check your connection and try again."
                )
            }
        }
    }

    fun retryJoin() {
        lastToken?.let { acceptInvite(it) }
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
        // "HH:mm" or the server's "HH:mm:ss" (Postgres TIME) → 12-hour display.
        // Only "HH:mm" used to parse, so the raw "08:30:00" was shown.
        val parts = time.split(":")
        if (parts.size < 2) return time
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
