package net.wellvo.android.viewmodels

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.wellvo.android.data.models.AppUser
import net.wellvo.android.network.ApiService
import net.wellvo.android.network.AutoJoinResult
import net.wellvo.android.network.WellvoError
import net.wellvo.android.services.AuthService
import net.wellvo.android.ui.navigation.AuthState
import net.wellvo.android.util.Validation
import javax.inject.Inject

data class AuthUiState(
    val phoneNumber: String = "",
    val otpCode: String = "",
    val isAwaitingOTP: Boolean = false,
    val isLoading: Boolean = false,
    val isGoogleLoading: Boolean = false,
    val errorMessage: String? = null,
    val email: String = "",
    val password: String = "",
    val displayName: String = "",
    val isSignUp: Boolean = false,
    val showReauthPrompt: Boolean = false
)

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authService: AuthService,
    private val apiService: ApiService
) : ViewModel() {

    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    private val _authState = MutableStateFlow<AuthState>(AuthState.Loading)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    private val _pendingAutoJoin = MutableStateFlow<AutoJoinResult?>(null)
    val pendingAutoJoin: StateFlow<AutoJoinResult?> = _pendingAutoJoin.asStateFlow()

    init {
        observeSessionStatus()
    }

    private fun observeSessionStatus() {
        viewModelScope.launch {
            authService.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> {
                        fetchUserAndAuthenticate()
                    }
                    is SessionStatus.NotAuthenticated -> {
                        val isRefreshFailure = status.isSignOut.not()
                        if (isRefreshFailure && _authState.value is AuthState.Authenticated) {
                            _uiState.value = _uiState.value.copy(showReauthPrompt = true)
                        }
                        _authState.value = AuthState.Unauthenticated
                    }
                    is SessionStatus.Initializing -> {
                        _authState.value = AuthState.Loading
                    }
                    is SessionStatus.RefreshFailure -> {
                        _uiState.value = _uiState.value.copy(showReauthPrompt = true)
                        _authState.value = AuthState.Unauthenticated
                    }
                }
            }
        }
    }

    private suspend fun fetchUserAndAuthenticate() {
        val user = authService.getCurrentUser()
        if (user != null) {
            checkAutoJoin()
            _authState.value = AuthState.Authenticated(user = user)
        } else {
            val userId = authService.currentUserId()
            if (userId != null) {
                checkAutoJoin()
                val fallbackUser = AppUser(
                    id = userId,
                    displayName = "",
                    role = net.wellvo.android.data.models.UserRole.Owner,
                    timezone = "America/New_York",
                    createdAt = "",
                    updatedAt = ""
                )
                _authState.value = AuthState.Authenticated(user = fallbackUser)
            } else {
                _authState.value = AuthState.Unauthenticated
            }
        }
    }

    private suspend fun checkAutoJoin() {
        try {
            val response = apiService.autoJoin()
            _pendingAutoJoin.value = apiService.checkAutoJoinResult(response)
        } catch (_: Exception) {
            _pendingAutoJoin.value = null
        }
    }

    fun clearAutoJoin() {
        _pendingAutoJoin.value = null
    }

    fun dismissReauthPrompt() {
        _uiState.value = _uiState.value.copy(showReauthPrompt = false)
    }

    fun updatePhoneNumber(phone: String) {
        _uiState.value = _uiState.value.copy(phoneNumber = phone, errorMessage = null)
    }

    fun updateOtpCode(code: String) {
        _uiState.value = _uiState.value.copy(otpCode = code, errorMessage = null)
    }

    fun updateEmail(email: String) {
        _uiState.value = _uiState.value.copy(email = email, errorMessage = null)
    }

    fun updatePassword(password: String) {
        _uiState.value = _uiState.value.copy(password = password, errorMessage = null)
    }

    fun updateDisplayName(name: String) {
        _uiState.value = _uiState.value.copy(displayName = name, errorMessage = null)
    }

    fun toggleSignUp() {
        _uiState.value = _uiState.value.copy(isSignUp = !_uiState.value.isSignUp, errorMessage = null)
    }

    fun sendOTP() {
        val phone = _uiState.value.phoneNumber
        if (!AuthService.isValidUSPhone(phone)) {
            _uiState.value = _uiState.value.copy(errorMessage = "Please enter a valid US phone number.")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                authService.sendPhoneOTP(phone)
                _uiState.value = _uiState.value.copy(isLoading = false, isAwaitingOTP = true)
            } catch (e: WellvoError) {
                _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = e.localizedMessage)
            }
        }
    }

    fun verifyOTP() {
        val phone = _uiState.value.phoneNumber
        val code = _uiState.value.otpCode

        if (code.length != 6) {
            _uiState.value = _uiState.value.copy(errorMessage = "Please enter the 6-digit code.")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                authService.verifyPhoneOTP(phone, code)
                _uiState.value = _uiState.value.copy(isLoading = false)
            } catch (e: WellvoError) {
                _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = e.localizedMessage)
            }
        }
    }

    fun signInWithEmail() {
        val state = _uiState.value

        if (!Validation.isValidEmail(state.email)) {
            _uiState.value = state.copy(errorMessage = "Please enter a valid email address.")
            return
        }

        if (state.isSignUp) {
            val nameError = Validation.displayNameError(state.displayName)
            if (nameError != null) {
                _uiState.value = state.copy(errorMessage = nameError)
                return
            }
            val pwError = Validation.passwordErrors(state.password)
            if (pwError != null) {
                _uiState.value = state.copy(errorMessage = pwError)
                return
            }
        } else if (state.password.isBlank()) {
            _uiState.value = state.copy(errorMessage = "Please enter your password.")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                if (state.isSignUp) {
                    authService.signUpWithEmail(state.email, state.password, state.displayName)
                } else {
                    authService.signInWithEmail(state.email, state.password)
                }
                _uiState.value = _uiState.value.copy(isLoading = false)
            } catch (e: WellvoError) {
                _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = e.localizedMessage)
            }
        }
    }

    fun signInWithGoogle(context: Context) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isGoogleLoading = true, errorMessage = null)
            try {
                authService.signInWithGoogle(context)
                _uiState.value = _uiState.value.copy(isGoogleLoading = false)
            } catch (e: WellvoError) {
                _uiState.value = _uiState.value.copy(isGoogleLoading = false, errorMessage = e.localizedMessage)
            }
        }
    }

    fun signOut() {
        viewModelScope.launch {
            authService.signOut()
            _uiState.value = AuthUiState()
        }
    }

    fun backToPhoneEntry() {
        _uiState.value = _uiState.value.copy(isAwaitingOTP = false, otpCode = "", errorMessage = null)
    }
}
