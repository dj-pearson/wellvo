package net.wellvo.android.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.MutableStateFlow
import net.wellvo.android.data.models.Mood
import net.wellvo.android.data.models.WellvoAlert
import net.wellvo.android.ui.screens.owner.DashboardScreen
import net.wellvo.android.viewmodels.DashboardViewModel
import net.wellvo.android.viewmodels.ReceiverCheckInStatus
import net.wellvo.android.viewmodels.ReceiverStatusCard
import net.wellvo.android.viewmodels.WeeklySummary
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = android.app.Application::class)
class DashboardScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private fun createViewModel(
        cards: List<ReceiverStatusCard> = emptyList(),
        summary: WeeklySummary? = null,
        isLoading: Boolean = false,
        errorMessage: String? = null,
        alerts: List<WellvoAlert> = emptyList()
    ): DashboardViewModel {
        return mockk(relaxed = true) {
            every { receiverCards } returns MutableStateFlow(cards)
            every { weeklySummary } returns MutableStateFlow(summary)
            every { this@mockk.isLoading } returns MutableStateFlow(isLoading)
            every { this@mockk.errorMessage } returns MutableStateFlow(errorMessage)
            every { successMessage } returns MutableStateFlow(null)
            every { sendingCheckInFor } returns MutableStateFlow(emptySet())
            every { cooldownUntil } returns MutableStateFlow(emptyMap())
            every { this@mockk.alerts } returns MutableStateFlow(alerts)
        }
    }

    @Test
    fun `empty state shows no receivers message`() {
        val viewModel = createViewModel()

        composeTestRule.setContent {
            DashboardScreen(
                viewModel = viewModel,
                userId = "test-user"
            )
        }

        composeTestRule.onNodeWithText("No Receivers Yet").assertIsDisplayed()
    }

    @Test
    fun `receiver cards render with correct status`() {
        val cards = listOf(
            ReceiverStatusCard(
                id = "1",
                memberId = "m1",
                name = "Mom",
                avatarUrl = null,
                status = ReceiverCheckInStatus.CheckedIn,
                lastCheckIn = "2026-03-27T09:00:00Z",
                streak = 5,
                mood = Mood.Happy,
                hasNotificationsEnabled = true,
                checkedInTime = "9:00 AM",
                locationLabel = null,
                kidResponseType = null
            )
        )
        val viewModel = createViewModel(cards = cards)

        composeTestRule.setContent {
            DashboardScreen(
                viewModel = viewModel,
                userId = "test-user"
            )
        }

        composeTestRule.onNodeWithText("Mom").assertIsDisplayed()
        composeTestRule.onNodeWithText("Checked In").assertIsDisplayed()
    }

    @Test
    fun `weekly summary displays when available`() {
        val cards = listOf(
            ReceiverStatusCard(
                id = "1",
                memberId = "m1",
                name = "Dad",
                avatarUrl = null,
                status = ReceiverCheckInStatus.Pending,
                lastCheckIn = null,
                streak = 0,
                mood = null,
                hasNotificationsEnabled = true,
                checkedInTime = null,
                locationLabel = null,
                kidResponseType = null
            )
        )
        val summary = WeeklySummary(
            consistencyPercentage = 85.0,
            averageCheckInTime = "9:15 AM",
            totalCheckIns = 6,
            totalExpected = 7,
            moodBreakdown = mapOf(Mood.Happy to 4, Mood.Neutral to 2)
        )
        val viewModel = createViewModel(cards = cards, summary = summary)

        composeTestRule.setContent {
            DashboardScreen(
                viewModel = viewModel,
                userId = "test-user"
            )
        }

        composeTestRule.onNodeWithText("85%").assertIsDisplayed()
        composeTestRule.onNodeWithText("9:15 AM").assertIsDisplayed()
    }

    @Test
    fun `loading state shows progress indicator`() {
        val viewModel = createViewModel(isLoading = true)

        composeTestRule.setContent {
            DashboardScreen(
                viewModel = viewModel,
                userId = "test-user"
            )
        }

        composeTestRule.onNodeWithText("Loading...").assertIsDisplayed()
    }
}
