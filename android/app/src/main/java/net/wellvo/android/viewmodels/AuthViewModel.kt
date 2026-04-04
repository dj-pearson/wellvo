package net.wellvo.android.viewmodels

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.wellvo.android.data.models.AppUser
import net.wellvo.android.network.ApiService
import net.wellvo.android.network.AutoJoinResult
import net.wellvo.android.network.WellvoError
import net.wellvo.android.services.AnalyticsService
import net.wellvo.android.services.AuthService
import net.wellvo.android.services.BiometricService
import net.wellvo.android.ui.navigation.AuthState
import net.wellvo.android.util.SecureStorage
import net.wellvo.android.util.Validation
import androidx.compose.runtime.Immutable
import javax.inject.Inject

@Immutable
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
    val showReauthPrompt: Boolean = false,
    val isResettingPassword: Boolean = false,
    val resetPasswordMessage: String? = null,
    val showBiometricSetupPrompt: Boolean = false,
    val biometricLocked: Boolean = false,
    val authLockoutMessage: String? = null,
    val authLockoutSecondsRemaining: Int = 0
)

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authService: AuthService,
    private val apiService: ApiService,
    private val analyticsService: AnalyticsService,
    val biometricService: BiometricService,
    private val secureStorage: SecureStorage
) : ViewModel() {

    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    // Rate limiting stored in encrypted storage
    private var failedAttempts: Int
        get() = secureStorage.loadInt(SecureStorage.AUTH_FAILED_ATTEMPTS)
        set(value) { secureStorage.saveInt(SecureStorage.AUTH_FAILED_ATTEMPTS, value) }
    private var lockoutUntilMs: Long
        get() = secureStorage.loadLong(SecureStorage.AUTH_LOCKOUT_UNTIL)
        set(value) { secureStorage.saveLong(SecureStorage.AUTH_LOCKOUT_UNTIL, value) }
    private var lockoutCountdownJob: Job? = null
    private var otpVerifyAttempts = 0
    private companion object {
        const val MAX_OTP_ATTEMPTS = 5
    }

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
            checkBiometricSetupPrompt()
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
        if (isLockedOut()) return

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                authService.sendPhoneOTP(phone)
                otpVerifyAttempts = 0
                _uiState.value = _uiState.value.copy(isLoading = false, isAwaitingOTP = true)
            } catch (e: WellvoError) {
                recordFailedAttempt()
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
        if (isLockedOut()) return

        otpVerifyAttempts++
        if (otpVerifyAttempts > MAX_OTP_ATTEMPTS) {
            _uiState.value = _uiState.value.copy(
                errorMessage = "Too many attempts. Please request a new code.",
                isAwaitingOTP = false,
                otpCode = ""
            )
            otpVerifyAttempts = 0
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                authService.verifyPhoneOTP(phone, code)
                analyticsService.track(AnalyticsService.SIGN_IN)
                resetFailedAttempts()
                _uiState.value = _uiState.value.copy(isLoading = false)
            } catch (e: WellvoError) {
                recordFailedAttempt()
                val remaining = MAX_OTP_ATTEMPTS - otpVerifyAttempts
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = "${e.localizedMessage} ($remaining attempts remaining)",
                    otpCode = ""
                )
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
        if (isLockedOut()) return

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            try {
                if (state.isSignUp) {
                    authService.signUpWithEmail(state.email, state.password, state.displayName)
                    analyticsService.track(AnalyticsService.SIGN_UP)
                } else {
                    authService.signInWithEmail(state.email, state.password)
                    analyticsService.track(AnalyticsService.SIGN_IN)
                }
                resetFailedAttempts()
                _uiState.value = _uiState.value.copy(isLoading = false, password = "")
            } catch (e: WellvoError) {
                recordFailedAttempt()
                // Don't reveal if email exists — use generic message for sign-in failures
                val safeMessage = if (state.isSignUp) e.localizedMessage else "Invalid email or password. Please try again."
                _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = safeMessage, password = "")
            }
        }
    }

    fun sendPasswordReset() {
        val state = _uiState.value
        if (!Validation.isValidEmail(state.email)) {
            _uiState.value = state.copy(errorMessage = "Please enter a valid email address.")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isResettingPassword = true, errorMessage = null, resetPasswordMessage = null)
            try {
                authService.resetPassword(state.email)
            } catch (_: Exception) {
                // Don't reveal whether the email exists
            }
            // Always show same message to avoid user enumeration
            _uiState.value = _uiState.value.copy(
                isResettingPassword = false,
                resetPasswordMessage = "If an account exists with that email, you'll receive a password reset link."
            )
        }
    }

    fun clearResetMessage() {
        _uiState.value = _uiState.value.copy(resetPasswordMessage = null)
    }

    fun signInWithGoogle(context: Context) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isGoogleLoading = true, errorMessage = null)
            try {
                authService.signInWithGoogle(context)
                analyticsService.track(AnalyticsService.SIGN_IN)
                _uiState.value = _uiState.value.copy(isGoogleLoading = false)
            } catch (e: WellvoError) {
                _uiState.value = _uiState.value.copy(isGoogleLoading = false, errorMessage = e.localizedMessage)
            }
        }
    }

    fun signOut() {
        viewModelScope.launch {
            analyticsService.track(AnalyticsService.SIGN_OUT)
            biometricService.reset()
            authService.signOut()
            _uiState.value = AuthUiState()
        }
    }

    // MARK: - Biometric

    fun checkBiometricSetupPrompt() {
        if (biometricService.shouldPromptToEnable()) {
            _uiState.value = _uiState.value.copy(showBiometricSetupPrompt = true)
        }
    }

    fun enableBiometric() {
        biometricService.isEnabled = true
        _uiState.value = _uiState.value.copy(showBiometricSetupPrompt = false)
    }

    fun skipBiometric() {
        biometricService.hasBeenSkipped = true
        _uiState.value = _uiState.value.copy(showBiometricSetupPrompt = false)
    }

    fun setBiometricLocked(locked: Boolean) {
        _uiState.value = _uiState.value.copy(biometricLocked = locked)
    }

    fun backToPhoneEntry() {
        _uiState.value = _uiState.value.copy(isAwaitingOTP = false, otpCode = "", errorMessage = null)
        otpVerifyAttempts = 0
    }

    // MARK: - Rate Limiting

    private fun isLockedOut(): Boolean {
        val until = lockoutUntilMs
        if (until > 0 && System.currentTimeMillis() < until) {
            startLockoutCountdown(until)
            return true
        }
        if (until > 0) {
            lockoutUntilMs = 0
            _uiState.value = _uiState.value.copy(authLockoutMessage = null, authLockoutSecondsRemaining = 0)
        }
        return false
    }

    private fun recordFailedAttempt() {
        failedAttempts += 1
        val count = failedAttempts
        when {
            count >= 10 -> {
                val until = System.currentTimeMillis() + 300_000 // 5 minutes
                lockoutUntilMs = until
                startLockoutCountdown(until)
            }
            count >= 5 -> {
                val until = System.currentTimeMillis() + 30_000 // 30 seconds
                lockoutUntilMs = until
                startLockoutCountdown(until)
            }
        }
    }

    private fun resetFailedAttempts() {
        failedAttempts = 0
        lockoutUntilMs = 0
        otpVerifyAttempts = 0
        lockoutCountdownJob?.cancel()
        _uiState.value = _uiState.value.copy(authLockoutMessage = null, authLockoutSecondsRemaining = 0)
    }

    override fun onCleared() {
        super.onCleared()
        lockoutCountdownJob?.cancel()
        lockoutCountdownJob = null
    }

    private fun startLockoutCountdown(untilMs: Long) {
        lockoutCountdownJob?.cancel()
        lockoutCountdownJob = viewModelScope.launch {
            while (true) {
                val remaining = ((untilMs - System.currentTimeMillis()) / 1000).toInt()
                if (remaining <= 0) {
                    _uiState.value = _uiState.value.copy(authLockoutMessage = null, authLockoutSecondsRemaining = 0)
                    break
                }
                _uiState.value = _uiState.value.copy(
                    authLockoutMessage = "Too many failed attempts. Try again in ${remaining}s.",
                    authLockoutSecondsRemaining = remaining
                )
                delay(1000)
            }
        }
    }
}
