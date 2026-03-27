package net.wellvo.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.wellvo.android.data.models.Family
import net.wellvo.android.data.models.FamilyMember
import net.wellvo.android.network.WellvoError
import net.wellvo.android.services.AnalyticsService
import net.wellvo.android.services.FamilyService
import javax.inject.Inject

@HiltViewModel
class FamilyViewModel @Inject constructor(
    private val familyService: FamilyService,
    private val analyticsService: AnalyticsService
) : ViewModel() {

    private val _family = MutableStateFlow<Family?>(null)
    val family: StateFlow<Family?> = _family.asStateFlow()

    private val _members = MutableStateFlow<List<FamilyMember>>(emptyList())
    val members: StateFlow<List<FamilyMember>> = _members.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _successMessage = MutableStateFlow<String?>(null)
    val successMessage: StateFlow<String?> = _successMessage.asStateFlow()

    private val _isInviting = MutableStateFlow(false)
    val isInviting: StateFlow<Boolean> = _isInviting.asStateFlow()

    private val _inviteSuccess = MutableStateFlow(false)
    val inviteSuccess: StateFlow<Boolean> = _inviteSuccess.asStateFlow()

    private val _inviteError = MutableStateFlow<String?>(null)
    val inviteError: StateFlow<String?> = _inviteError.asStateFlow()

    fun loadFamily(userId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val fetchedFamily = familyService.getFamily(userId) ?: run {
                    _isLoading.value = false
                    return@launch
                }
                _family.value = fetchedFamily
                _members.value = familyService.getFamilyMembers(fetchedFamily.id)
            } catch (e: WellvoError) {
                _errorMessage.value = e.localizedMessage
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to load family."
            }
            _isLoading.value = false
        }
    }

    fun removeMember(memberId: String, memberName: String) {
        viewModelScope.launch {
            try {
                familyService.removeMember(memberId)
                analyticsService.track(AnalyticsService.RECEIVER_REMOVED)
                _successMessage.value = "$memberName has been removed."
                _family.value?.let { loadFamily(it.ownerId) }
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to remove member."
            }
        }
    }

    fun resendInvite(member: FamilyMember) {
        val familyId = _family.value?.id ?: return
        viewModelScope.launch {
            try {
                familyService.inviteReceiver(
                    familyId = familyId,
                    name = member.user?.displayName ?: "Family Member",
                    phone = member.user?.phone ?: "",
                    checkinTime = "08:00"
                )
                _successMessage.value = "Invite re-sent to ${member.user?.displayName ?: "member"}."
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to re-send invite."
            }
        }
    }

    fun transferOwnership(memberId: String, memberName: String) {
        val familyId = _family.value?.id ?: return
        viewModelScope.launch {
            try {
                familyService.transferOwnership(memberId = memberId, familyId = familyId)
                _successMessage.value = "Ownership transferred to $memberName."
                loadFamily(_family.value?.ownerId ?: return@launch)
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to transfer ownership."
            }
        }
    }

    fun inviteReceiver(name: String, phone: String, checkinTime: String, receiverMode: String = "standard") {
        val familyId = _family.value?.id ?: run {
            _inviteError.value = "No family found. Please create a family first."
            return
        }
        viewModelScope.launch {
            _isInviting.value = true
            _inviteError.value = null
            try {
                familyService.inviteReceiver(
                    familyId = familyId,
                    name = name,
                    phone = phone,
                    checkinTime = checkinTime,
                    receiverMode = receiverMode
                )
                analyticsService.track(AnalyticsService.RECEIVER_INVITED)
                _inviteSuccess.value = true
                _successMessage.value = "Invitation sent to $name."
                _family.value?.let { loadFamily(it.ownerId) }
            } catch (e: WellvoError.Network) {
                _inviteError.value = "Network error. Please check your connection and try again."
            } catch (e: WellvoError) {
                _inviteError.value = e.message ?: "Failed to send invitation."
            } catch (e: Exception) {
                _inviteError.value = e.message ?: "Failed to send invitation."
            }
            _isInviting.value = false
        }
    }

    fun resetInviteState() {
        _isInviting.value = false
        _inviteSuccess.value = false
        _inviteError.value = null
    }

    fun clearError() {
        _errorMessage.value = null
    }

    fun clearSuccessMessage() {
        _successMessage.value = null
    }
}
