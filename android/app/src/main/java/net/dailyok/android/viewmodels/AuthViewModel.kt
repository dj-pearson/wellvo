package net.dailyok.android.viewmodels

import net.dailyok.android.services.PushNotificationService

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
import net.dailyok.android.data.models.AppUser
import net.dailyok.android.network.ApiService
import net.dailyok.android.network.AutoJoinResult
import net.dailyok.android.network.DailyOKError
import net.dailyok.android.network.JoinPreviewOutcome
import net.dailyok.android.network.JoinPreviews
import net.dailyok.android.services.AnalyticsService
import net.dailyok.android.services.AuthService
import net.dailyok.android.services.BiometricService
import net.dailyok.android.ui.navigation.AuthState
import net.dailyok.android.util.SecureStorage
import net.dailyok.android.util.Validation
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

/**
 * Where a signed-in user belongs, from their actual family membership.
 * Only [None] — a confirmed "no family" — means "ask how they'll use the app".
 */
sealed interface Membership {
    data object Resolving : Membership
    data object Failed : Membership
    data object None : Membership
    data class Member(val role: net.dailyok.android.data.models.UserRole) : Membership
}

/** What a user with no family chose on the start screen. */
enum class SetupChoice { None, OwnerSetup, CodeEntry }

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authService: AuthService,
    private val apiService: ApiService,
    private val analyticsService: AnalyticsService,
    val biometricService: BiometricService,
    private val secureStorage: SecureStorage,
    private val pushNotificationService: PushNotificationService
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

    private val _membership = MutableStateFlow<Membership>(Membership.Resolving)
    val membership: StateFlow<Membership> = _membership.asStateFlow()

    private val _setupChoice = MutableStateFlow(SetupChoice.None)
    val setupChoice: StateFlow<SetupChoice> = _setupChoice.asStateFlow()

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
                        resetSessionState()
                        _authState.value = AuthState.Unauthenticated
                    }
                    is SessionStatus.Initializing -> {
                        _authState.value = AuthState.Loading
                    }
                    is SessionStatus.RefreshFailure -> {
                        _uiState.value = _uiState.value.copy(showReauthPrompt = true)
                        resetSessionState()
                        _authState.value = AuthState.Unauthenticated
                    }
                }
            }
        }
    }

    private suspend fun fetchUserAndAuthenticate() {
        // Register this device for push as soon as someone is signed in. Off
        // the critical path: routing must not wait on Firebase.
        authService.currentUserId()?.let { userId ->
            viewModelScope.launch { pushNotificationService.onSignedIn(userId) }
        }
        val user = authService.getCurrentUser()
        if (user != null) {
            // Keep users.timezone aligned with device zone so the edge
            // function dedup, the owner dashboard's "today" window and the
            // receiver's scheduled prompts never drift.
            authService.syncTimezoneIfChanged()
            _authState.value = AuthState.Authenticated(user = user)
            checkBiometricSetupPrompt()
        } else {
            val userId = authService.currentUserId()
            if (userId != null) {
                // The profile row couldn't be read (offline). Routing no longer
                // reads a role from here, so this placeholder can't send anyone
                // to the owner screens; membership decides.
                val fallbackUser = AppUser(
                    id = userId,
                    displayName = "",
                    role = net.dailyok.android.data.models.UserRole.Owner,
                    timezone = "America/New_York",
                    createdAt = "",
                    updatedAt = ""
                )
                _authState.value = AuthState.Authenticated(user = fallbackUser)
            } else {
                _authState.value = AuthState.Unauthenticated
                return
            }
        }
        // Once per signed-in user. SessionStatus.Authenticated re-emits on every
        // token refresh; re-resolving then could yank a receiver out of their
        // onboarding (permission step) the moment the join landed.
        if (authService.currentUserId() != resolvedForUserId) {
            resolveMembership()
        }
    }

    /** The user whose membership has been resolved this session. */
    private var resolvedForUserId: String? = null

    /** Nothing about the previous account may route the next one. */
    private fun resetSessionState() {
        _membership.value = Membership.Resolving
        _setupChoice.value = SetupChoice.None
        _pendingAutoJoin.value = null
        resolvedForUserId = null
        // onNewToken must not register a rotated token for a signed-out user.
        secureStorage.delete(SecureStorage.USER_ID)
    }

    /**
     * Work out where this user belongs: the cached role at once (so an offline
     * launch opens the right app), then the server's answer. A failed lookup
     * never falls back to owner. With no membership, try a phone-number invite
     * match before asking the user.
     */
    suspend fun resolveMembership() {
        val userId = authService.currentUserId() ?: return
        val current = _membership.value
        if (current !is Membership.Member) {
            cachedRole(userId)?.let { _membership.value = Membership.Member(it) }
        }

        val role = try {
            authService.currentMembershipRole()
        } catch (_: Exception) {
            if (_membership.value !is Membership.Member) _membership.value = Membership.Failed
            return
        }

        if (role != null) {
            setMember(userId, role)
            _pendingAutoJoin.value = null
            resolvedForUserId = userId
            return
        }

        cacheRole(userId, null)
        if (checkAutoJoin()) {
            // A server that predates `preview` joined at once: route by the
            // role it actually made instead of asking about a done join.
            val joinedRole = runCatching { authService.currentMembershipRole() }.getOrNull()
            if (joinedRole != null) {
                setMember(userId, joinedRole)
                resolvedForUserId = userId
                return
            }
        }
        _membership.value = Membership.None
        resolvedForUserId = userId
    }

    /**
     * This user's membership changed from inside the app (ownership handed
     * to a co-caregiver, or they left the family): ask the server again.
     */
    fun onMembershipChanged() {
        _setupChoice.value = SetupChoice.None
        _pendingAutoJoin.value = null
        _membership.value = Membership.Resolving
        viewModelScope.launch { resolveMembership() }
    }

    /**
     * A join finished (link, code or phone match): ask the server what it made
     * this user rather than assuming receiver — a code can make someone a viewer.
     */
    fun onJoinedResolveRole() {
        _setupChoice.value = SetupChoice.None
        _pendingAutoJoin.value = null
        _membership.value = Membership.Resolving
        viewModelScope.launch { resolveMembership() }
    }

    /**
     * Leaving owner setup. If the family was already created they are its owner
     * now, so re-resolve instead of dropping them back at the start choice.
     */
    fun leaveOwnerSetup() {
        _setupChoice.value = SetupChoice.None
        _membership.value = Membership.Resolving
        viewModelScope.launch { resolveMembership() }
    }

    fun retryMembership() {
        viewModelScope.launch { resolveMembership() }
    }

    /** A join or owner setup finished: route by the new role immediately. */
    fun onJoined(role: net.dailyok.android.data.models.UserRole) {
        val userId = authService.currentUserId() ?: return
        setMember(userId, role)
        _pendingAutoJoin.value = null
        _setupChoice.value = SetupChoice.None
    }

    /** Invite / auto-join abandoned: back to the start choice. */
    fun onJoinCancelled() {
        _pendingAutoJoin.value = null
        _setupChoice.value = SetupChoice.None
        if (_membership.value !is Membership.Member) _membership.value = Membership.None
    }

    fun chooseOwnerSetup() { _setupChoice.value = SetupChoice.OwnerSetup }
    fun chooseCodeEntry() { _setupChoice.value = SetupChoice.CodeEntry }
    fun clearSetupChoice() { _setupChoice.value = SetupChoice.None }

    private fun setMember(userId: String, role: net.dailyok.android.data.models.UserRole) {
        _membership.value = Membership.Member(role)
        cacheRole(userId, role)
    }

    private fun cachedRole(userId: String): net.dailyok.android.data.models.UserRole? =
        secureStorage.load("cached_role_$userId")?.let {
            runCatching { net.dailyok.android.data.models.UserRole.valueOf(it) }.getOrNull()
        }

    private fun cacheRole(userId: String, role: net.dailyok.android.data.models.UserRole?) {
        if (role == null) secureStorage.delete("cached_role_$userId")
        else secureStorage.save("cached_role_$userId", role.name)
    }

    /**
     * Is there an invite for this account's verified phone number? Asks
     * without joining (auto-join `preview`, edge pass 6): the join used to
     * happen here, before the person had seen whose family it was. The
     * receiver onboarding screen shows the family and joins on "Join".
     *
     * Returns true when the server joined anyway (one that predates
     * `preview`, or they were already in the family).
     */
    private suspend fun checkAutoJoin(): Boolean {
        return try {
            when (val outcome = JoinPreviews.interpret(apiService.previewAutoJoin())) {
                is JoinPreviewOutcome.AskFirst -> {
                    val preview = outcome.preview
                    _pendingAutoJoin.value = AutoJoinResult(
                        familyId = preview.familyId ?: "",
                        role = preview.role ?: "receiver",
                        checkinTime = preview.checkinTime,
                        preview = preview
                    )
                    false
                }
                is JoinPreviewOutcome.AlreadyJoined -> {
                    _pendingAutoJoin.value = null
                    true
                }
                is JoinPreviewOutcome.NoInvite -> {
                    _pendingAutoJoin.value = null
                    false
                }
            }
        } catch (_: Exception) {
            _pendingAutoJoin.value = null
            false
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
            } catch (e: DailyOKError) {
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
            } catch (e: DailyOKError) {
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
            } catch (e: DailyOKError) {
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
            } catch (e: DailyOKError) {
                _uiState.value = _uiState.value.copy(isGoogleLoading = false, errorMessage = e.localizedMessage)
            }
        }
    }

    fun signOut() {
        viewModelScope.launch {
            analyticsService.track(AnalyticsService.SIGN_OUT)
            biometricService.reset()
            // Before the session goes: deactivating the token needs it.
            pushNotificationService.onSignedOut()
            authService.signOut()
            resetSessionState()
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
