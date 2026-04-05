package net.wellvo.android.util

import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * Pure functions for computing check-in streaks and consistency badges
 * from a list of ISO-8601 timestamps.
 *
 * Client-side computation so no schema change is required.
 */
object Streaks {

    /**
     * Current streak = consecutive calendar days up to today (or yesterday
     * if today has no check-in yet) with at least one check-in.
     *
     * @param isoTimestamps list of `checked_in_at` strings (ISO-8601)
     * @param zone timezone to bucket timestamps into calendar days
     */
    fun currentStreak(
        isoTimestamps: List<String>,
        zone: ZoneId = ZoneId.systemDefault(),
        today: LocalDate = LocalDate.now(zone)
    ): Int {
        if (isoTimestamps.isEmpty()) return 0
        val days = isoTimestamps
            .mapNotNull { parseDay(it, zone) }
            .toSortedSet(reverseOrder())

        if (days.isEmpty()) return 0

        // If today is not in the set, allow counting from yesterday so that
        // the streak doesn't visually break mid-day before the user checks in.
        var cursor = if (days.contains(today)) today else today.minusDays(1)
        var streak = 0
        while (days.contains(cursor)) {
            streak += 1
            cursor = cursor.minusDays(1)
        }
        return streak
    }

    /**
     * Consistency percentage for the last [windowDays] days (default 7).
     * Returns a value in 0..100.
     */
    fun consistencyPercent(
        isoTimestamps: List<String>,
        windowDays: Int = 7,
        zone: ZoneId = ZoneId.systemDefault(),
        today: LocalDate = LocalDate.now(zone)
    ): Int {
        if (windowDays <= 0) return 0
        val windowStart = today.minusDays((windowDays - 1).toLong())
        val days = isoTimestamps
            .mapNotNull { parseDay(it, zone) }
            .filter { !it.isBefore(windowStart) && !it.isAfter(today) }
            .toSet()
        return ((days.size.toDouble() / windowDays) * 100).toInt().coerceIn(0, 100)
    }

    /**
     * Maps a consistency percentage to a badge tier.
     * - Gold: 100%
     * - Silver: ≥ 80%
     * - Bronze: ≥ 50%
     * - None: < 50%
     */
    fun badge(consistencyPercent: Int): ConsistencyBadge = when {
        consistencyPercent >= 100 -> ConsistencyBadge.Gold
        consistencyPercent >= 80 -> ConsistencyBadge.Silver
        consistencyPercent >= 50 -> ConsistencyBadge.Bronze
        else -> ConsistencyBadge.None
    }

    private fun parseDay(iso: String, zone: ZoneId): LocalDate? = try {
        ZonedDateTime.parse(iso, DateTimeFormatter.ISO_DATE_TIME)
            .withZoneSameInstant(zone)
            .toLocalDate()
    } catch (_: Throwable) {
        try {
            // Fallback: some timestamps may be `yyyy-MM-dd'T'HH:mm:ss` (no zone).
            LocalDate.parse(iso.substring(0, 10))
        } catch (_: Throwable) {
            null
        }
    }
}

enum class ConsistencyBadge { Gold, Silver, Bronze, None }
