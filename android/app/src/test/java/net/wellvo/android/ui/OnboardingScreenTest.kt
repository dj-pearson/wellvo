package net.wellvo.android.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.flow.MutableStateFlow
import net.wellvo.android.ui.screens.onboarding.OnboardingScreen
import net.wellvo.android.viewmodels.OnboardingStep
import net.wellvo.android.viewmodels.OnboardingUiState
import net.wellvo.android.viewmodels.OnboardingViewModel
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = android.app.Application::class)
class OnboardingScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun createViewModel(
        state: OnboardingUiState = OnboardingUiState(),
        stepIndex: Int = 0,
        totalSteps: Int = 7
    ): OnboardingViewModel {
        return mockk(relaxed = true) {
            every { uiState } returns MutableStateFlow(state)
            every { this@mockk.stepIndex } returns stepIndex
            every { this@mockk.totalSteps } returns totalSteps
        }
    }

    @Test
    fun `welcome step displays correctly`() {
        val viewModel = createViewModel(
            OnboardingUiState(currentStep = OnboardingStep.Welcome)
        )

        composeTestRule.setContent {
            OnboardingScreen(viewModel = viewModel)
        }

        composeTestRule.onNodeWithText("Welcome to Wellvo").assertIsDisplayed()
        composeTestRule.onNodeWithText("Get Started").assertIsDisplayed()
    }

    @Test
    fun `user type step shows all options`() {
        val viewModel = createViewModel(
            state = OnboardingUiState(currentStep = OnboardingStep.UserType),
            stepIndex = 1
        )

        composeTestRule.setContent {
            OnboardingScreen(viewModel = viewModel)
        }

        composeTestRule.onNodeWithText("Who are you checking in on?").assertIsDisplayed()
        composeTestRule.onNodeWithText("Aging Parent").assertIsDisplayed()
        composeTestRule.onNodeWithText("Teenager").assertIsDisplayed()
        composeTestRule.onNodeWithText("Someone Else").assertIsDisplayed()
    }

    @Test
    fun `create family step has input and button`() {
        val viewModel = createViewModel(
            state = OnboardingUiState(currentStep = OnboardingStep.CreateFamily),
            stepIndex = 2
        )

        composeTestRule.setContent {
            OnboardingScreen(viewModel = viewModel)
        }

        composeTestRule.onNodeWithText("Name your family group").assertIsDisplayed()
        composeTestRule.onNodeWithText("Create Family").assertIsDisplayed()
    }

    @Test
    fun `back button calls goBack`() {
        val viewModel = createViewModel(
            state = OnboardingUiState(currentStep = OnboardingStep.UserType),
            stepIndex = 1
        )

        composeTestRule.setContent {
            OnboardingScreen(viewModel = viewModel)
        }

        // Step indicator shows progress
        composeTestRule.onNodeWithText("Step 2 of 7").assertIsDisplayed()
    }

    @Test
    fun `choose plan step shows all plans`() {
        val viewModel = createViewModel(
            state = OnboardingUiState(currentStep = OnboardingStep.ChoosePlan),
            stepIndex = 3
        )

        composeTestRule.setContent {
            OnboardingScreen(viewModel = viewModel)
        }

        composeTestRule.onNodeWithText("Choose your plan").assertIsDisplayed()
        composeTestRule.onNodeWithText("Free").assertIsDisplayed()
        composeTestRule.onNodeWithText("$4.99/mo", substring = true).assertIsDisplayed()
        composeTestRule.onNodeWithText("$9.99/mo", substring = true).assertIsDisplayed()
    }

    @Test
    fun `complete step shows dashboard button`() {
        val viewModel = createViewModel(
            state = OnboardingUiState(currentStep = OnboardingStep.Complete),
            stepIndex = 6
        )

        composeTestRule.setContent {
            OnboardingScreen(viewModel = viewModel)
        }

        composeTestRule.onNodeWithText("You're all set!").assertIsDisplayed()
        composeTestRule.onNodeWithText("Go to Dashboard").assertIsDisplayed()
    }
}
