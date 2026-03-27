package net.wellvo.android.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import net.wellvo.android.data.models.Mood
import net.wellvo.android.ui.screens.receiver.MoodSelector
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MoodSelectorTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun `standard mode shows 3 moods`() {
        composeTestRule.setContent {
            MoodSelector(
                isKidMode = false,
                selectedMood = null,
                onSelectMood = {},
                onSubmit = {},
                onSkip = {}
            )
        }

        composeTestRule.onNodeWithText("Good").assertIsDisplayed()
        composeTestRule.onNodeWithText("Okay").assertIsDisplayed()
        composeTestRule.onNodeWithText("Tired").assertIsDisplayed()
        // Kid-only moods should not show
        composeTestRule.onNodeWithText("Excited").assertDoesNotExist()
    }

    @Test
    fun `kid mode shows all 8 moods`() {
        composeTestRule.setContent {
            MoodSelector(
                isKidMode = true,
                selectedMood = null,
                onSelectMood = {},
                onSubmit = {},
                onSkip = {}
            )
        }

        composeTestRule.onNodeWithText("Good").assertIsDisplayed()
        composeTestRule.onNodeWithText("Okay").assertIsDisplayed()
        composeTestRule.onNodeWithText("Tired").assertIsDisplayed()
        composeTestRule.onNodeWithText("Excited").assertIsDisplayed()
        composeTestRule.onNodeWithText("Bored").assertIsDisplayed()
        composeTestRule.onNodeWithText("Hungry").assertIsDisplayed()
        composeTestRule.onNodeWithText("Scared").assertIsDisplayed()
        composeTestRule.onNodeWithText("Having Fun").assertIsDisplayed()
    }

    @Test
    fun `selecting mood calls onSelect callback`() {
        var selectedMood: Mood? = null
        composeTestRule.setContent {
            MoodSelector(
                isKidMode = false,
                selectedMood = null,
                onSelectMood = { selectedMood = it },
                onSubmit = {},
                onSkip = {}
            )
        }

        composeTestRule.onNodeWithText("Good").performClick()
        assertEquals(Mood.Happy, selectedMood)
    }

    @Test
    fun `skip button calls onSkip callback`() {
        var skipped = false
        composeTestRule.setContent {
            MoodSelector(
                isKidMode = false,
                selectedMood = null,
                onSelectMood = {},
                onSubmit = {},
                onSkip = { skipped = true }
            )
        }

        composeTestRule.onNodeWithText("Skip").performClick()
        assertEquals(true, skipped)
    }
}
