package net.wellvo.android.viewmodels

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import net.wellvo.android.data.models.Family
import net.wellvo.android.network.ApiService
import net.wellvo.android.network.WellvoError
import net.wellvo.android.services.AuthService
import javax.inject.Inject

enum class OnboardingStep {
    Welcome,
    UserType,
    CreateFamily,
    ChoosePlan,
    AddReceiver,
    Notifications,
    Complete
}

enum class UserTypeSelection(val serialName: String, val label: String, val description: String) {
    AgingParent("aging_parent", "Aging Parent", "Keep tabs on Mom or Dad"),
    Teenager("teenager", "Teenager", "A simple daily check-in"),
    Other("other", "Someone Else", "Friend, roommate, or other")
}

data class OnboardingUiState(
    val currentStep: OnboardingStep = OnboardingStep.Welcome,
    val selectedUserType: UserTypeSelection? = null,
    val familyName: String = "",
    val createdFamily: Family? = null,
    val selectedPlan: String = "free",
    val receiverName: String = "",
    val receiverPhone: String = "",
    val checkinHour: Int = 9,
    val checkinMinute: Int = 0,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val notificationPermissionGranted: Boolean = false,
    val isComplete: Boolean = false
)

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val apiService: ApiService,
    private val savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        OnboardingUiState(
            currentStep = OnboardingStep.valueOf(
                savedStateHandle.get<String>("currentStep") ?: "Welcome"
            ),
            familyName = savedStateHandle.get<String>("familyName") ?: "",
            receiverName = savedStateHandle.get<String>("receiverName") ?: "",
            receiverPhone = savedStateHandle.get<String>("receiverPhone") ?: "",
            selectedPlan = savedStateHandle.get<String>("selectedPlan") ?: "free",
            checkinHour = savedStateHandle.get<Int>("checkinHour") ?: 9,
            checkinMinute = savedStateHandle.get<Int>("checkinMinute") ?: 0
        )
    )
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()

    val stepIndex: Int
        get() = OnboardingStep.entries.indexOf(_uiState.value.currentStep)

    val totalSteps: Int = OnboardingStep.entries.size

    fun selectUserType(type: UserTypeSelection) {
        _uiState.value = _uiState.value.copy(selectedUserType = type, errorMessage = null)
        advance()
    }

    fun updateFamilyName(name: String) {
        _uiState.value = _uiState.value.copy(familyName = name, errorMessage = null)
        savedStateHandle["familyName"] = name
    }

    fun updateReceiverName(name: String) {
        _uiState.value = _uiState.value.copy(receiverName = name, errorMessage = null)
        savedStateHandle["receiverName"] = name
    }

    fun updateReceiverPhone(phone: String) {
        _uiState.value = _uiState.value.copy(receiverPhone = phone, errorMessage = null)
        savedStateHandle["receiverPhone"] = phone
    }

    fun updateCheckinTime(hour: Int, minute: Int) {
        _uiState.value = _uiState.value.copy(checkinHour = hour, checkinMinute = minute)
        savedStateHandle["checkinHour"] = hour
        savedStateHandle["checkinMinute"] = minute
    }

    fun selectPlan(plan: String) {
        _uiState.value = _uiState.value.copy(selectedPlan = plan, errorMessage = null)
        savedStateHandle["selectedPlan"] = plan
    }

    fun createFamily() {
        val name = _uiState.value.familyName.trim()
        if (name.isEmpty()) {
            _uiState.value = _uiState.value.copy(errorMessage = "Please enter a family name.")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                val userId = supabase.auth.currentUserOrNull()?.id
                    ?: throw WellvoError.Auth("Not signed in.")

                val family = supabase.postgrest.from("families")
                    .insert(buildJsonObject {
                        put("name", name)
                        put("owner_id", userId)
                    }) {
                        select()
                    }
                    .decodeSingle<Family>()

                // Also create family_members entry for the owner
                supabase.postgrest.from("family_members")
                    .insert(buildJsonObject {
                        put("family_id", family.id)
                        put("user_id", userId)
                        put("role", "owner")
                        put("status", "active")
                    })

                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    createdFamily = family
                )
                advance()
            } catch (e: WellvoError) {
                _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = e.localizedMessage)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = e.message ?: "Failed to create family.")
            }
        }
    }

    fun inviteReceiver() {
        val state = _uiState.value
        val family = state.createdFamily
        if (family == null) {
            _uiState.value = state.copy(errorMessage = "Please create a family first.")
            return
        }
        if (state.receiverName.isBlank()) {
            _uiState.value = state.copy(errorMessage = "Please enter the receiver's name.")
            return
        }
        if (!AuthService.isValidUSPhone(state.receiverPhone)) {
            _uiState.value = state.copy(errorMessage = "Please enter a valid US phone number.")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                apiService.inviteReceiver(
                    net.wellvo.android.network.InviteReceiverRequest(
                        familyId = family.id,
                        phone = state.receiverPhone,
                        displayName = state.receiverName,
                        receiverMode = state.selectedUserType?.serialName ?: "standard"
                    )
                )
                _uiState.value = _uiState.value.copy(isLoading = false)
                advance()
            } catch (e: WellvoError) {
                _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = e.localizedMessage)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = e.message ?: "Failed to invite receiver.")
            }
        }
    }

    fun skipAddReceiver() {
        advance()
    }

    fun onNotificationPermissionResult(granted: Boolean) {
        _uiState.value = _uiState.value.copy(notificationPermissionGranted = granted)
        advance()
    }

    fun checkNotificationPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun advance() {
        val steps = OnboardingStep.entries
        val currentIndex = steps.indexOf(_uiState.value.currentStep)
        if (currentIndex < steps.size - 1) {
            val nextStep = steps[currentIndex + 1]
            _uiState.value = _uiState.value.copy(currentStep = nextStep, errorMessage = null)
            savedStateHandle["currentStep"] = nextStep.name
        }
        if (_uiState.value.currentStep == OnboardingStep.Complete) {
            _uiState.value = _uiState.value.copy(isComplete = true)
        }
    }

    fun goBack() {
        val steps = OnboardingStep.entries
        val currentIndex = steps.indexOf(_uiState.value.currentStep)
        if (currentIndex > 0) {
            val prevStep = steps[currentIndex - 1]
            _uiState.value = _uiState.value.copy(currentStep = prevStep, errorMessage = null)
            savedStateHandle["currentStep"] = prevStep.name
        }
    }
}
