package net.wellvo.android.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.MutableStateFlow
import net.wellvo.android.ui.screens.receiver.ReceiverHomeScreen
import net.wellvo.android.viewmodels.ReceiverUiState
import net.wellvo.android.viewmodels.ReceiverViewModel
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = android.app.Application::class)
class ReceiverHomeScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun createViewModel(
        state: ReceiverUiState = ReceiverUiState(isLoading = false),
        isOffline: Boolean = false,
        pendingOfflineCount: Int = 0
    ): ReceiverViewModel {
        return mockk(relaxed = true) {
            every { uiState } returns MutableStateFlow(state)
            every { this@mockk.isOffline } returns MutableStateFlow(isOffline)
            every { this@mockk.pendingOfflineCount } returns MutableStateFlow(pendingOfflineCount)
        }
    }

    @Test
    fun `check-in button visible and clickable when not checked in`() {
        val viewModel = createViewModel(
            ReceiverUiState(
                isLoading = false,
                hasCheckedInToday = false
            )
        )

        composeTestRule.setContent {
            ReceiverHomeScreen(viewModel = viewModel)
        }

        composeTestRule.onNodeWithText("I'm OK").assertIsDisplayed()
    }

    @Test
    fun `status card appears after check-in`() {
        val viewModel = createViewModel(
            ReceiverUiState(
                isLoading = false,
                hasCheckedInToday = true,
                showMoodSelector = false
            )
        )

        composeTestRule.setContent {
            ReceiverHomeScreen(viewModel = viewModel)
        }

        composeTestRule.onNodeWithText("You're all set!").assertIsDisplayed()
        composeTestRule.onNodeWithText("Checked in today").assertIsDisplayed()
    }

    @Test
    fun `mood selector appears when enabled`() {
        val viewModel = createViewModel(
            ReceiverUiState(
                isLoading = false,
                hasCheckedInToday = true,
                showMoodSelector = true,
                isKidMode = false
            )
        )

        composeTestRule.setContent {
            ReceiverHomeScreen(viewModel = viewModel)
        }

        composeTestRule.onNodeWithText("You're all set!").assertIsDisplayed()
        // MoodSelector should be visible — it shows mood options
        composeTestRule.onNodeWithText("How are you feeling?").assertExists()
    }

    @Test
    fun `offline banner shows when offline`() {
        val viewModel = createViewModel(
            state = ReceiverUiState(isLoading = false, hasCheckedInToday = false),
            isOffline = true
        )

        composeTestRule.setContent {
            ReceiverHomeScreen(viewModel = viewModel)
        }

        composeTestRule.onNodeWithText("You're offline. Check-ins will be saved and synced later.")
            .assertIsDisplayed()
    }
}
