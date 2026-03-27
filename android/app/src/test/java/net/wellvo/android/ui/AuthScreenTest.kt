package net.wellvo.android.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertDoesNotExist
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick

import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.flow.MutableStateFlow
import net.wellvo.android.ui.screens.auth.AuthScreen
import net.wellvo.android.viewmodels.AuthUiState
import net.wellvo.android.viewmodels.AuthViewModel
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AuthScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun createMockViewModel(state: AuthUiState = AuthUiState()): AuthViewModel {
        return mockk(relaxed = true) {
            every { uiState } returns MutableStateFlow(state)
            every { authState } returns MutableStateFlow(net.wellvo.android.ui.navigation.AuthState.Unauthenticated)
            every { pendingAutoJoin } returns MutableStateFlow(null)
        }
    }

    @Test
    fun `auth screen shows all three auth options`() {
        val vm = createMockViewModel()
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Sign in with your phone").assertIsDisplayed()
        composeTestRule.onNodeWithText("Send Code").assertIsDisplayed()
        composeTestRule.onNodeWithText("Continue with Google").assertIsDisplayed()
        composeTestRule.onNodeWithText("Sign in with email").assertIsDisplayed()
    }

    @Test
    fun `auth screen shows Wellvo branding`() {
        val vm = createMockViewModel()
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Wellvo").assertIsDisplayed()
        composeTestRule.onNodeWithText("One tap. Peace of mind.").assertIsDisplayed()
    }

    @Test
    fun `phone OTP flow shows verification code input`() {
        val vm = createMockViewModel(
            AuthUiState(phoneNumber = "2125551234", isAwaitingOTP = true)
        )
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Enter verification code").assertIsDisplayed()
        composeTestRule.onNodeWithText("Verify").assertIsDisplayed()
        composeTestRule.onNodeWithText("Use a different number").assertIsDisplayed()
    }

    @Test
    fun `validation errors display correctly`() {
        val vm = createMockViewModel(
            AuthUiState(errorMessage = "Please enter a valid US phone number.")
        )
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Please enter a valid US phone number.").assertIsDisplayed()
    }

    @Test
    fun `send code button calls viewModel sendOTP`() {
        val vm = createMockViewModel()
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Send Code").performClick()
        verify { vm.sendOTP() }
    }

    @Test
    fun `loading state replaces send code with progress indicator`() {
        val vm = createMockViewModel(AuthUiState(isLoading = true))
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        // When loading, the button is replaced by CircularProgressIndicator
        composeTestRule.onNodeWithText("Send Code").assertDoesNotExist()
    }
}
