package net.dailyok.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.dailyok.android.data.models.Family
import net.dailyok.android.data.models.FamilyMember
import net.dailyok.android.network.DailyOKError
import net.dailyok.android.services.AnalyticsService
import net.dailyok.android.services.FamilyService
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
                val members = familyService.getFamilyMembers(fetchedFamily.id)
                _members.value = members
                _viewerSeats.value = FamilySeats.viewerSeats(members, fetchedFamily.maxViewers)
            } catch (e: DailyOKError) {
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

    /** An invite waiting for the owner to send it from their messaging app. */
    private val _inviteToSend = MutableStateFlow<net.dailyok.android.util.InviteToSend?>(null)
    val inviteToSend: StateFlow<net.dailyok.android.util.InviteToSend?> = _inviteToSend.asStateFlow()

    /** The screen opened the messaging app for [inviteToSend]. */
    fun onInviteHandedOff() {
        _inviteToSend.value = null
    }

    fun resendInvite(member: FamilyMember) {
        val familyId = _family.value?.id ?: return
        if (member.user?.phone.isNullOrBlank()) {
            _errorMessage.value = "No phone number on file for ${member.user?.displayName ?: "this member"}. Remove them and invite again with their number."
            return
        }
        viewModelScope.launch {
            try {
                _inviteToSend.value = familyService.inviteReceiver(
                    familyId = familyId,
                    name = member.user?.displayName ?: "Family Member",
                    phone = member.user?.phone ?: "",
                    checkinTime = "08:00",
                    // A co-caregiver's re-send must stay a co-caregiver invite.
                    role = if (member.role == net.dailyok.android.data.models.UserRole.Viewer) "viewer" else "receiver"
                )
                _successMessage.value = "New invite ready for ${member.user?.displayName ?: "member"}."
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to re-send invite."
            }
        }
    }

    /**
     * Set once ownership has moved away from this user. The screen then asks
     * the app to re-resolve their role, which routes them to the co-caregiver
     * tabs (they stay in the family as a co-caregiver).
     */
    private val _ownershipTransferred = MutableStateFlow(false)
    val ownershipTransferred: StateFlow<Boolean> = _ownershipTransferred.asStateFlow()

    fun onOwnershipTransferHandled() {
        _ownershipTransferred.value = false
    }

    /**
     * Hand the family to [member], who must be an active co-caregiver: the
     * server refuses a receiver (they are the person being checked on).
     */
    fun transferOwnership(member: FamilyMember) {
        val familyId = _family.value?.id ?: return
        val memberName = member.user?.displayName?.takeIf { it.isNotBlank() } ?: "them"
        if (!FamilySeats.canReceiveOwnership(member)) {
            _errorMessage.value = "Ownership can only go to an active co-caregiver."
            return
        }
        viewModelScope.launch {
            try {
                familyService.transferOwnership(newOwnerUserId = member.userId, familyId = familyId)
                _successMessage.value = "Ownership transferred to $memberName."
                _ownershipTransferred.value = true
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to transfer ownership."
            }
        }
    }

    /** Active co-caregivers and the plan's co-caregiver seats. */
    val viewerSeats: StateFlow<FamilySeats.Seats> get() = _viewerSeats.asStateFlow()
    private val _viewerSeats = MutableStateFlow(FamilySeats.Seats(used = 0, max = 0))

    /**
     * Invite a co-caregiver: someone who sees check-ins and gets the alerts,
     * but is never asked to check in. Separate from inviting a receiver, and
     * limited by the plan's co-caregiver seats (families.max_viewers).
     */
    fun inviteCoCaregiver(name: String, phone: String) {
        val familyId = _family.value?.id ?: run {
            _inviteError.value = "No family found. Please create a family first."
            return
        }
        val seats = _viewerSeats.value
        if (seats.isFull) {
            _inviteError.value = FamilySeats.fullMessage(seats)
            return
        }
        viewModelScope.launch {
            _isInviting.value = true
            _inviteError.value = null
            try {
                _inviteToSend.value = familyService.inviteReceiver(
                    familyId = familyId,
                    name = name,
                    phone = phone,
                    checkinTime = "08:00",
                    role = "viewer"
                )
                _inviteSuccess.value = true
                _successMessage.value = "Invite ready for $name — send it from your messages."
                _family.value?.let { loadFamily(it.ownerId) }
            } catch (e: DailyOKError.Network) {
                _inviteError.value = "Network error. Please check your connection and try again."
            } catch (e: DailyOKError.Rejected) {
                _inviteError.value = if (e.status == 403) {
                    "Your plan has no free co-caregiver seats. Upgrade, or remove a co-caregiver first."
                } else {
                    e.message ?: "Failed to send invitation."
                }
            } catch (e: Exception) {
                _inviteError.value = e.message ?: "Failed to send invitation."
            }
            _isInviting.value = false
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
                _inviteToSend.value = familyService.inviteReceiver(
                    familyId = familyId,
                    name = name,
                    phone = phone,
                    checkinTime = checkinTime,
                    receiverMode = receiverMode
                )
                analyticsService.track(AnalyticsService.RECEIVER_INVITED)
                _inviteSuccess.value = true
                _successMessage.value = "Invite ready for $name — send it from your messages."
                _family.value?.let { loadFamily(it.ownerId) }
            } catch (e: DailyOKError.Network) {
                _inviteError.value = "Network error. Please check your connection and try again."
            } catch (e: DailyOKError) {
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
