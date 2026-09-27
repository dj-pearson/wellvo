package net.dailyok.android.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertDoesNotExist
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick

import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.flow.MutableStateFlow
import net.dailyok.android.ui.screens.auth.AuthScreen
import net.dailyok.android.viewmodels.AuthUiState
import net.dailyok.android.viewmodels.AuthViewModel
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
            every { authState } returns MutableStateFlow(net.dailyok.android.ui.navigation.AuthState.Unauthenticated)
            every { pendingAutoJoin } returns MutableStateFlow(null)
        }
    }

    @Test
    fun `auth screen offers Google and email, not phone`() {
        val vm = createMockViewModel()
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Continue with Google").assertIsDisplayed()
        composeTestRule.onNodeWithText("Sign in with email").assertIsDisplayed()
        composeTestRule.onNodeWithText("Sign in with your phone").assertDoesNotExist()
        composeTestRule.onNodeWithText("Send Code").assertDoesNotExist()
    }

    @Test
    fun `auth screen shows Daily OK branding`() {
        val vm = createMockViewModel()
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Daily OK").assertIsDisplayed()
        composeTestRule.onNodeWithText("One tap. Peace of mind.").assertIsDisplayed()
    }

    @Test
    fun `phone account help explains how to get back in`() {
        val vm = createMockViewModel()
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Signed up with a phone number?").performClick()
        composeTestRule.onNodeWithText("Contact support").assertIsDisplayed()
    }

    @Test
    fun `validation errors display correctly`() {
        val vm = createMockViewModel(
            AuthUiState(errorMessage = "Please enter a valid email address.")
        )
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Please enter a valid email address.").assertIsDisplayed()
    }

    @Test
    fun `sign in button calls viewModel signInWithEmail`() {
        val vm = createMockViewModel()
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Sign In").performClick()
        verify { vm.signInWithEmail() }
    }

    @Test
    fun `loading state replaces sign in with progress indicator`() {
        val vm = createMockViewModel(AuthUiState(isLoading = true))
        composeTestRule.setContent { AuthScreen(viewModel = vm) }

        composeTestRule.onNodeWithText("Sign In").assertDoesNotExist()
    }
}
