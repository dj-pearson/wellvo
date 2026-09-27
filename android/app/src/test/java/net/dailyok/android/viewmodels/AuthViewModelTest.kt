package net.dailyok.android.viewmodels

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
import net.dailyok.android.data.models.AppUser
import net.dailyok.android.data.models.UserRole
import net.dailyok.android.network.ApiService
import net.dailyok.android.network.AutoJoinResponse
import net.dailyok.android.network.JoinPreview
import net.dailyok.android.network.DailyOKError
import net.dailyok.android.services.AnalyticsService
import net.dailyok.android.services.AuthService
import net.dailyok.android.ui.navigation.AuthState
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
        // Sign-in asks about a phone-number invite without joining (preview).
        coEvery { apiService.previewAutoJoin() } returns JoinPreview(matched = false, reason = "no_matching_invite")
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel(): AuthViewModel {
        return AuthViewModel(
            authService,
            apiService,
            analyticsService,
            biometricService = mockk(relaxed = true),
            secureStorage = mockk(relaxed = true),
            pushNotificationService = mockk(relaxed = true)
        )
    }

    @Test
    fun `initial state is loading`() = runTest {
        val vm = createViewModel()
        assertEquals(AuthState.Loading, vm.authState.value)
        assertEquals(AuthUiState(), vm.uiState.value)
    }

    // Phone-number sign-in was retired; accounts without an email are asked to add one.

    @Test
    fun `phone-only account is asked to add an email after sign-in`() = runTest {
        val testUser = AppUser(
            id = "user-1", displayName = "Mom", role = UserRole.Receiver,
            timezone = "UTC", createdAt = "", updatedAt = ""
        )
        coEvery { authService.getCurrentUser() } returns testUser
        every { authService.signedInAccountLacksEmail() } returns true
        val vm = createViewModel()
        sessionStatusFlow.value = SessionStatus.Authenticated(mockk(relaxed = true))
        advanceUntilIdle()
        assertEquals(AddEmailStage.EnterEmail, vm.uiState.value.addEmailStage)
    }

    @Test
    fun `account with an email is not asked`() = runTest {
        every { authService.signedInAccountLacksEmail() } returns false
        val vm = createViewModel()
        vm.checkAccountHasEmail()
        assertEquals(AddEmailStage.Hidden, vm.uiState.value.addEmailStage)
    }

    @Test
    fun `not now closes the prompt for this launch`() = runTest {
        every { authService.signedInAccountLacksEmail() } returns true
        val vm = createViewModel()
        vm.checkAccountHasEmail()
        vm.deferAddEmail()
        assertEquals(AddEmailStage.Hidden, vm.uiState.value.addEmailStage)
        vm.checkAccountHasEmail()
        assertEquals(AddEmailStage.Hidden, vm.uiState.value.addEmailStage)
    }

    @Test
    fun `add email rejects an invalid address`() = runTest {
        val vm = createViewModel()
        vm.updateAddEmailAddress("not-an-email")
        vm.sendAddEmailCode()
        advanceUntilIdle()
        assertEquals("Please enter a valid email address.", vm.uiState.value.addEmailError)
        coVerify(exactly = 0) { authService.requestAddEmail(any()) }
    }

    @Test
    fun `add email sends a code then confirms it`() = runTest {
        every { authService.signedInAccountLacksEmail() } returns true
        val vm = createViewModel()
        vm.checkAccountHasEmail()
        vm.updateAddEmailAddress("mom@example.com")
        vm.sendAddEmailCode()
        advanceUntilIdle()
        coVerify { authService.requestAddEmail("mom@example.com") }
        assertEquals(AddEmailStage.EnterCode, vm.uiState.value.addEmailStage)

        vm.updateAddEmailCode("12 34 56")
        assertEquals("123456", vm.uiState.value.addEmailCode)
        vm.confirmAddEmailCode()
        advanceUntilIdle()
        coVerify { authService.confirmAddedEmail("mom@example.com", "123456") }
        assertEquals(AddEmailStage.Done, vm.uiState.value.addEmailStage)
    }

    @Test
    fun `wrong add-email code keeps the code step with an error`() = runTest {
        coEvery { authService.confirmAddedEmail(any(), any()) } throws DailyOKError.Auth("Invalid code.")
        every { authService.signedInAccountLacksEmail() } returns true
        val vm = createViewModel()
        vm.checkAccountHasEmail()
        vm.updateAddEmailAddress("mom@example.com")
        vm.sendAddEmailCode()
        advanceUntilIdle()
        vm.updateAddEmailCode("000000")
        vm.confirmAddEmailCode()
        advanceUntilIdle()
        assertEquals(AddEmailStage.EnterCode, vm.uiState.value.addEmailStage)
        assertTrue(vm.uiState.value.addEmailError!!.contains("incorrect"))
    }

    @Test
    fun `not now while the code is being sent keeps the prompt closed`() = runTest {
        every { authService.signedInAccountLacksEmail() } returns true
        coEvery { authService.requestAddEmail(any()) } coAnswers { kotlinx.coroutines.delay(1_000) }
        val vm = createViewModel()
        vm.checkAccountHasEmail()
        vm.updateAddEmailAddress("mom@example.com")
        vm.sendAddEmailCode()
        vm.deferAddEmail()
        advanceUntilIdle()
        assertEquals(AddEmailStage.Hidden, vm.uiState.value.addEmailStage)
        assertFalse(vm.uiState.value.isAddingEmail)
    }

    @Test
    fun `accountLacksEmail is true only without an address`() {
        assertTrue(AuthService.accountLacksEmail(null))
        assertTrue(AuthService.accountLacksEmail(" "))
        assertFalse(AuthService.accountLacksEmail("mom@example.com"))
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
    fun `session authenticated triggers user fetch`() = runTest {
        val testUser = AppUser(
            id = "user-1", displayName = "Test", role = UserRole.Owner,
            timezone = "UTC", createdAt = "", updatedAt = ""
        )
        coEvery { authService.getCurrentUser() } returns testUser
        val vm = createViewModel()
        sessionStatusFlow.value = SessionStatus.Authenticated(mockk(relaxed = true))
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
