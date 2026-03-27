package net.wellvo.android.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.wellvo.android.data.models.AppUser
import net.wellvo.android.network.WellvoError
import net.wellvo.android.services.AnalyticsService
import net.wellvo.android.services.AuthService
import net.wellvo.android.services.FamilyService
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val authService: AuthService,
    private val familyService: FamilyService,
    private val analyticsService: AnalyticsService
) : ViewModel() {

    private val _user = MutableStateFlow<AppUser?>(null)
    val user: StateFlow<AppUser?> = _user.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _successMessage = MutableStateFlow<String?>(null)
    val successMessage: StateFlow<String?> = _successMessage.asStateFlow()

    private val _isGoogleLinked = MutableStateFlow(false)
    val isGoogleLinked: StateFlow<Boolean> = _isGoogleLinked.asStateFlow()

    private val _isExporting = MutableStateFlow(false)
    val isExporting: StateFlow<Boolean> = _isExporting.asStateFlow()

    private val _exportedData = MutableStateFlow<String?>(null)
    val exportedData: StateFlow<String?> = _exportedData.asStateFlow()

    private val _retentionDays = MutableStateFlow(365)
    val retentionDays: StateFlow<Int> = _retentionDays.asStateFlow()

    private val _signedOut = MutableStateFlow(false)
    val signedOut: StateFlow<Boolean> = _signedOut.asStateFlow()

    private val _showDeleteConfirmation = MutableStateFlow(false)
    val showDeleteConfirmation: StateFlow<Boolean> = _showDeleteConfirmation.asStateFlow()

    private val _showSignOutConfirmation = MutableStateFlow(false)
    val showSignOutConfirmation: StateFlow<Boolean> = _showSignOutConfirmation.asStateFlow()

    private var familyId: String? = null

    fun loadSettings(userId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                _user.value = authService.getCurrentUser()
                _isGoogleLinked.value = authService.isGoogleLinked()

                val family = familyService.getFamily(userId)
                familyId = family?.id
                if (family != null) {
                    _retentionDays.value = authService.getDataRetention(family.id)
                }
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to load settings."
            }
            _isLoading.value = false
        }
    }

    fun signOut() {
        viewModelScope.launch {
            try {
                authService.signOut()
                _signedOut.value = true
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to sign out."
            }
        }
    }

    fun requestSignOut() {
        _showSignOutConfirmation.value = true
    }

    fun dismissSignOutConfirmation() {
        _showSignOutConfirmation.value = false
    }

    fun confirmSignOut() {
        _showSignOutConfirmation.value = false
        signOut()
    }

    fun requestDeleteAccount() {
        _showDeleteConfirmation.value = true
    }

    fun dismissDeleteConfirmation() {
        _showDeleteConfirmation.value = false
    }

    fun confirmDeleteAccount() {
        _showDeleteConfirmation.value = false
        deleteAccount()
    }

    private fun deleteAccount() {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                authService.deleteAccount()
                _signedOut.value = true
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to delete account."
            }
            _isLoading.value = false
        }
    }

    fun exportUserData() {
        viewModelScope.launch {
            _isExporting.value = true
            try {
                val data = authService.exportUserData()
                _exportedData.value = data
                _successMessage.value = "Data exported successfully."
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to export data."
            }
            _isExporting.value = false
        }
    }

    fun clearExportedData() {
        _exportedData.value = null
    }

    fun updateRetentionDays(days: Int) {
        val fId = familyId ?: return
        _retentionDays.value = days
        viewModelScope.launch {
            try {
                authService.updateDataRetention(fId, days)
                analyticsService.track(AnalyticsService.SETTINGS_SAVED)
                _successMessage.value = "Data retention updated."
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to update data retention."
            }
        }
    }

    fun linkGoogleAccount(context: android.content.Context) {
        viewModelScope.launch {
            try {
                authService.signInWithGoogle(context)
                _isGoogleLinked.value = true
                _successMessage.value = "Google account linked."
            } catch (e: WellvoError) {
                _errorMessage.value = e.message
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to link Google account."
            }
        }
    }

    fun clearError() {
        _errorMessage.value = null
    }

    fun clearSuccessMessage() {
        _successMessage.value = null
    }
}
