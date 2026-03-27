package net.wellvo.android.viewmodels

import net.wellvo.android.data.models.CheckIn
import net.wellvo.android.data.models.CheckInSource
import net.wellvo.android.data.models.Mood
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.format.DateTimeFormatter

class DashboardViewModelTest {

    @Test
    fun `calculateStreak returns 0 for empty check-ins`() {
        val streak = calculateStreakHelper(emptyList())
        assertEquals(0, streak)
    }

    @Test
    fun `calculateStreak counts consecutive days from today`() {
        val today = LocalDate.now()
        val checkIns = listOf(
            makeCheckIn(today),
            makeCheckIn(today.minusDays(1)),
            makeCheckIn(today.minusDays(2))
        )
        assertEquals(3, calculateStreakHelper(checkIns))
    }

    @Test
    fun `calculateStreak breaks on gap`() {
        val today = LocalDate.now()
        val checkIns = listOf(
            makeCheckIn(today),
            makeCheckIn(today.minusDays(1)),
            // gap at -2
            makeCheckIn(today.minusDays(3))
        )
        assertEquals(2, calculateStreakHelper(checkIns))
    }

    @Test
    fun `calculateStreak returns 0 if no check-in today`() {
        val today = LocalDate.now()
        val checkIns = listOf(
            makeCheckIn(today.minusDays(1)),
            makeCheckIn(today.minusDays(2))
        )
        assertEquals(0, calculateStreakHelper(checkIns))
    }

    @Test
    fun `computeWeeklySummary calculates consistency percentage`() {
        val today = LocalDate.now()
        val checkIns = listOf(
            makeCheckIn(today, "09:00"),
            makeCheckIn(today.minusDays(1), "08:30"),
            makeCheckIn(today.minusDays(2), "09:30")
        )
        val summary = computeWeeklySummaryHelper(checkIns, receiverCount = 1)
        // 3 check-ins / 7 expected = ~42.86%
        assertEquals(42.0, summary.consistencyPercentage, 1.0)
        assertEquals(3, summary.totalCheckIns)
        assertEquals(7, summary.totalExpected)
    }

    @Test
    fun `computeWeeklySummary with zero receivers returns 0 consistency`() {
        val summary = computeWeeklySummaryHelper(emptyList(), receiverCount = 0)
        assertEquals(0.0, summary.consistencyPercentage, 0.01)
        assertEquals("--", summary.averageCheckInTime)
    }

    @Test
    fun `computeWeeklySummary calculates mood breakdown`() {
        val today = LocalDate.now()
        val checkIns = listOf(
            makeCheckIn(today, "09:00", Mood.Happy),
            makeCheckIn(today.minusDays(1), "09:00", Mood.Happy),
            makeCheckIn(today.minusDays(2), "09:00", Mood.Tired)
        )
        val summary = computeWeeklySummaryHelper(checkIns, receiverCount = 1)
        assertEquals(2, summary.moodBreakdown[Mood.Happy])
        assertEquals(1, summary.moodBreakdown[Mood.Tired])
    }

    @Test
    fun `computeWeeklySummary with 100 percent consistency`() {
        val today = LocalDate.now()
        val checkIns = (0L until 7L).map { days ->
            makeCheckIn(today.minusDays(days), "09:00")
        }
        val summary = computeWeeklySummaryHelper(checkIns, receiverCount = 1)
        assertEquals(100.0, summary.consistencyPercentage, 0.01)
        assertEquals(7, summary.totalCheckIns)
    }

    @Test
    fun `ReceiverStatusCard data class holds all fields`() {
        val card = ReceiverStatusCard(
            id = "r1", memberId = "m1", name = "Alice", avatarUrl = null,
            status = ReceiverCheckInStatus.CheckedIn, lastCheckIn = "2026-03-26T09:00:00",
            streak = 5, mood = Mood.Happy, hasNotificationsEnabled = true,
            checkedInTime = "2026-03-26T09:00:00", locationLabel = "home",
            kidResponseType = null
        )
        assertEquals("Alice", card.name)
        assertEquals(ReceiverCheckInStatus.CheckedIn, card.status)
        assertEquals(5, card.streak)
        assertEquals(Mood.Happy, card.mood)
    }

    // -- Helper functions that mirror the ViewModel's private methods --

    private fun calculateStreakHelper(checkIns: List<CheckIn>): Int {
        if (checkIns.isEmpty()) return 0
        val checkInDays = checkIns.mapNotNull { checkIn ->
            try {
                LocalDate.parse(checkIn.checkedInAt.substring(0, 10))
            } catch (_: Exception) { null }
        }.toSet()

        var streak = 0
        var currentDate = LocalDate.now()
        while (checkInDays.contains(currentDate)) {
            streak++
            currentDate = currentDate.minusDays(1)
        }
        return streak
    }

    private fun computeWeeklySummaryHelper(checkIns: List<CheckIn>, receiverCount: Int): WeeklySummary {
        val totalExpected = receiverCount * 7
        val totalCheckIns = checkIns.size
        val consistency = if (totalExpected > 0) {
            (totalCheckIns.toDouble() / totalExpected.toDouble()) * 100
        } else 0.0

        val avgTime = if (checkIns.isNotEmpty()) {
            val totalMinutes = checkIns.sumOf { checkIn ->
                try {
                    val parts = checkIn.checkedInAt.substringAfter("T").take(5).split(":")
                    parts[0].toInt() * 60 + parts[1].toInt()
                } catch (_: Exception) { 0 }
            }
            val avgMinutes = totalMinutes / checkIns.size
            val hour = avgMinutes / 60
            val minute = avgMinutes % 60
            java.time.LocalTime.of(hour.coerceIn(0, 23), minute.coerceIn(0, 59))
                .format(DateTimeFormatter.ofPattern("h:mm a"))
        } else "--"

        val moodBreakdown = mutableMapOf<Mood, Int>()
        for (checkIn in checkIns) {
            val mood = checkIn.mood ?: continue
            moodBreakdown[mood] = (moodBreakdown[mood] ?: 0) + 1
        }

        return WeeklySummary(
            consistencyPercentage = consistency,
            averageCheckInTime = avgTime,
            totalCheckIns = totalCheckIns,
            totalExpected = totalExpected,
            moodBreakdown = moodBreakdown
        )
    }

    private fun makeCheckIn(
        date: LocalDate,
        time: String = "09:00",
        mood: Mood? = null
    ): CheckIn {
        return CheckIn(
            id = "ci-${date}",
            receiverId = "r1",
            familyId = "f1",
            checkedInAt = "${date}T${time}:00",
            mood = mood,
            source = CheckInSource.App
        )
    }
}
