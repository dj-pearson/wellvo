package net.wellvo.android.viewmodels

import io.github.jan.supabase.auth.status.SessionStatus
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import net.wellvo.android.data.models.AppUser
import net.wellvo.android.data.models.UserRole
import net.wellvo.android.network.ApiService
import net.wellvo.android.network.AutoJoinResponse
import net.wellvo.android.network.WellvoError
import net.wellvo.android.services.AnalyticsService
import net.wellvo.android.services.AuthService
import net.wellvo.android.ui.navigation.AuthState
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AuthViewModelTest {

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var authService: AuthService
    private lateinit var apiService: ApiService
    private lateinit var analyticsService: AnalyticsService
    private lateinit var sessionStatusFlow: MutableStateFlow<SessionStatus>

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        sessionStatusFlow = MutableStateFlow(SessionStatus.Initializing)
        authService = mockk(relaxed = true) {
            every { sessionStatus } returns sessionStatusFlow
        }
        apiService = mockk(relaxed = true)
        analyticsService = mockk(relaxed = true)
        coEvery { apiService.autoJoin() } returns AutoJoinResponse(
            matched = false,
            alreadyMember = false,
            familyId = null,
            role = null,
            checkinTime = null
        )
        coEvery { apiService.checkAutoJoinResult(any()) } returns null
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel(): AuthViewModel {
        return AuthViewModel(authService, apiService, analyticsService)
    }

    @Test
    fun `initial state is loading`() = runTest {
        val vm = createViewModel()
        assertEquals(AuthState.Loading, vm.authState.value)
        assertEquals(AuthUiState(), vm.uiState.value)
    }

    @Test
    fun `updatePhoneNumber updates state and clears error`() = runTest {
        val vm = createViewModel()
        vm.updatePhoneNumber("5551234567")
        assertEquals("5551234567", vm.uiState.value.phoneNumber)
        assertNull(vm.uiState.value.errorMessage)
    }

    @Test
    fun `sendOTP with invalid phone sets error`() = runTest {
        val vm = createViewModel()
        vm.updatePhoneNumber("123") // too short
        vm.sendOTP()
        advanceUntilIdle()
        assertEquals("Please enter a valid US phone number.", vm.uiState.value.errorMessage)
        assertFalse(vm.uiState.value.isAwaitingOTP)
    }

    @Test
    fun `sendOTP with valid phone transitions to awaiting OTP`() = runTest {
        val vm = createViewModel()
        vm.updatePhoneNumber("2125551234")
        coEvery { authService.sendPhoneOTP(any()) } returns Unit
        vm.sendOTP()
        advanceUntilIdle()
        assertTrue(vm.uiState.value.isAwaitingOTP)
        assertNull(vm.uiState.value.errorMessage)
    }

    @Test
    fun `sendOTP network error sets error message`() = runTest {
        val vm = createViewModel()
        vm.updatePhoneNumber("2125551234")
        coEvery { authService.sendPhoneOTP(any()) } throws WellvoError.Network()
        vm.sendOTP()
        advanceUntilIdle()
        assertFalse(vm.uiState.value.isAwaitingOTP)
        assertTrue(vm.uiState.value.errorMessage?.contains("Network") == true)
    }

    @Test
    fun `verifyOTP with short code sets error`() = runTest {
        val vm = createViewModel()
        vm.updateOtpCode("123")
        vm.verifyOTP()
        advanceUntilIdle()
        assertEquals("Please enter the 6-digit code.", vm.uiState.value.errorMessage)
    }

    @Test
    fun `verifyOTP with valid code calls authService and tracks analytics`() = runTest {
        val vm = createViewModel()
        vm.updatePhoneNumber("2125551234")
        vm.updateOtpCode("123456")
        coEvery { authService.verifyPhoneOTP(any(), any()) } returns Unit
        vm.verifyOTP()
        advanceUntilIdle()
        coVerify { authService.verifyPhoneOTP(any(), "123456") }
        verify { analyticsService.track(AnalyticsService.SIGN_IN) }
        assertNull(vm.uiState.value.errorMessage)
    }

    @Test
    fun `signInWithEmail validates email format`() = runTest {
        val vm = createViewModel()
        vm.updateEmail("not-an-email")
        vm.updatePassword("Password1!")
        vm.signInWithEmail()
        advanceUntilIdle()
        assertEquals("Please enter a valid email address.", vm.uiState.value.errorMessage)
    }

    @Test
    fun `signInWithEmail with blank password sets error`() = runTest {
        val vm = createViewModel()
        vm.updateEmail("user@example.com")
        vm.updatePassword("")
        vm.signInWithEmail()
        advanceUntilIdle()
        assertEquals("Please enter your password.", vm.uiState.value.errorMessage)
    }

    @Test
    fun `signInWithEmail calls authService on valid input`() = runTest {
        val vm = createViewModel()
        vm.updateEmail("user@example.com")
        vm.updatePassword("password")
        coEvery { authService.signInWithEmail(any(), any()) } returns Unit
        vm.signInWithEmail()
        advanceUntilIdle()
        coVerify { authService.signInWithEmail("user@example.com", "password") }
        verify { analyticsService.track(AnalyticsService.SIGN_IN) }
    }

    @Test
    fun `toggleSignUp flips isSignUp flag`() = runTest {
        val vm = createViewModel()
        assertFalse(vm.uiState.value.isSignUp)
        vm.toggleSignUp()
        assertTrue(vm.uiState.value.isSignUp)
        vm.toggleSignUp()
        assertFalse(vm.uiState.value.isSignUp)
    }

    @Test
    fun `backToPhoneEntry resets OTP state`() = runTest {
        val vm = createViewModel()
        vm.updateOtpCode("123456")
        vm.backToPhoneEntry()
        assertEquals("", vm.uiState.value.otpCode)
        assertFalse(vm.uiState.value.isAwaitingOTP)
        assertNull(vm.uiState.value.errorMessage)
    }

    @Test
    fun `session authenticated triggers user fetch`() = runTest {
        val testUser = AppUser(
            id = "user-1", displayName = "Test", role = UserRole.Owner,
            timezone = "UTC", createdAt = "", updatedAt = ""
        )
        coEvery { authService.getCurrentUser() } returns testUser
        val vm = createViewModel()
        sessionStatusFlow.value = SessionStatus.Authenticated
        advanceUntilIdle()
        val state = vm.authState.value
        assertTrue(state is AuthState.Authenticated)
        assertEquals("user-1", (state as AuthState.Authenticated).user.id)
    }

    @Test
    fun `signOut resets ui state and calls authService`() = runTest {
        val vm = createViewModel()
        vm.updateEmail("user@example.com")
        vm.signOut()
        advanceUntilIdle()
        assertEquals(AuthUiState(), vm.uiState.value)
        coVerify { authService.signOut() }
    }
}
