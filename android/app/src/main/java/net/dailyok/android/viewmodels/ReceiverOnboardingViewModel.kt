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
    val ownerName: String? = null,
    /**
     * The family they were invited to, waiting for "Join". Nothing has been
     * joined while this is set.
     */
    val consent: net.dailyok.android.network.JoinPreview? = null
)

@HiltViewModel
class ReceiverOnboardingViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val familyService: net.dailyok.android.services.FamilyService,
    private val apiService: net.dailyok.android.network.ApiService
) : ViewModel() {

    private var lastToken: String? = null

    /** The phone-match invite being asked about (auto-join), if any. */
    private var autoJoinFamilyId: String? = null

    /**
     * Start from what brought them here: an invite link ([token]) or an invite
     * matching their phone number ([autoJoin]). Either way the family is shown
     * first and nothing is joined until they tap "Join".
     */
    fun start(token: String?, autoJoin: net.dailyok.android.network.AutoJoinResult?) {
        when {
            token != null -> previewInvite(token)
            autoJoin?.preview != null -> {
                autoJoinFamilyId = autoJoin.familyId.takeIf { it.isNotBlank() }
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = null,
                    joinFailed = false,
                    consent = autoJoin.preview
                )
            }
            else -> loadReceiverSettings()
        }
    }

    private fun previewInvite(token: String) {
        lastToken = token
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null, joinFailed = false)
            try {
                when (val outcome = net.dailyok.android.network.JoinPreviews.interpret(apiService.previewInvite(token))) {
                    is net.dailyok.android.network.JoinPreviewOutcome.AskFirst ->
                        _uiState.value = _uiState.value.copy(isLoading = false, consent = outcome.preview)
                    // Already in, or an older server that joined at once.
                    is net.dailyok.android.network.JoinPreviewOutcome.AlreadyJoined ->
                        onJoined(role = outcome.role, ownerName = null, checkinTime = null)
                    is net.dailyok.android.network.JoinPreviewOutcome.NoInvite ->
                        _uiState.value = _uiState.value.copy(isLoading = false, joinFailed = true, errorMessage = null)
                }
            } catch (e: net.dailyok.android.network.DailyOKError.Rejected) {
                if (e.status == 409) {
                    onJoined(role = null, ownerName = null, checkinTime = null)
                } else {
                    _uiState.value = _uiState.value.copy(isLoading = false, joinFailed = true, errorMessage = e.message)
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    joinFailed = true,
                    errorMessage = e.message ?: "Couldn't load the invite. Check your connection and try again."
                )
            }
        }
    }

    /** "Join" on the consent card. */
    fun confirmJoin() {
        val token = lastToken
        if (token != null) {
            acceptInvite(token)
            return
        }
        val familyId = autoJoinFamilyId
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                val response = apiService.autoJoin(familyId)
                if (response.matched) {
                    onJoined(role = response.role, ownerName = _uiState.value.consent?.presentableOwner, checkinTime = response.checkinTime)
                } else {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        consent = null,
                        joinFailed = true,
                        errorMessage = if (response.reason == "limit_reached") {
                            "This family has no free places right now. Ask the person who invited you to make room, then try again."
                        } else {
                            "This invite is no longer valid. Ask the person who invited you to send a new one."
                        }
                    )
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = e.message ?: "Couldn't join. Check your connection and try again."
                )
            }
        }
    }

    /**
     * Joined: follow the role the server made. A co-caregiver has no check-in
     * schedule or check-in steps, so they go straight on (the app then routes
     * them to the co-caregiver screens).
     */
    private fun onJoined(role: String?, ownerName: String?, checkinTime: String?) {
        if (role == "viewer") {
            _uiState.value = _uiState.value.copy(isLoading = false, consent = null, isComplete = true)
            return
        }
        _uiState.value = _uiState.value.copy(
            consent = null,
            checkinTime = checkinTime?.let { formatTime(it) } ?: _uiState.value.checkinTime,
            ownerName = ownerName?.takeIf { it.isNotBlank() && it != "User" } ?: _uiState.value.ownerName
        )
        loadReceiverSettings()
    }

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
                    .select(columns = io.github.jan.supabase.postgrest.query.Columns.raw(FamilyMember.COLUMNS)) {
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
                        .select(columns = io.github.jan.supabase.postgrest.query.Columns.raw(net.dailyok.android.data.models.AppUser.MEMBER_COLUMNS)) {
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
                onJoined(role = joined.role, ownerName = joined.ownerName, checkinTime = joined.checkinTime)
            } catch (e: net.dailyok.android.network.DailyOKError.Rejected) {
                if (e.status == 409) {
                    // "Already a member of this family" — the link tapped twice.
                    onJoined(role = null, ownerName = null, checkinTime = null)
                } else {
                    _uiState.value = _uiState.value.copy(isLoading = false, joinFailed = true, consent = null, errorMessage = e.message)
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    joinFailed = true,
                    consent = null,
                    errorMessage = e.message ?: "Couldn't join. Check your connection and try again."
                )
            }
        }
    }

    /** Try Again after a failure: show the family again rather than joining blind. */
    fun retryJoin() {
        lastToken?.let { previewInvite(it) }
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
