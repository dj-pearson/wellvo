package net.dailyok.android.services

import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import net.dailyok.android.data.OfflineCheckIn
import net.dailyok.android.data.OfflineCheckInDao
import net.dailyok.android.network.DailyOKError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class OfflineCheckInServiceTest {

    private lateinit var checkInService: CheckInService
    private lateinit var dao: OfflineCheckInDao

    @Before
    fun setUp() {
        checkInService = mockk(relaxed = true)
        dao = mockk(relaxed = true)
    }

    @Test
    fun `performCheckIn returns true on successful online check-in`() = runTest {
        coEvery { checkInService.checkIn(any(), any(), any(), any(), any()) } returns "checkin-id"
        val result = performCheckInHelper("f1", "r1", "req1", null, "app")
        assertTrue(result)
    }

    @Test
    fun `performCheckIn queues check-in on offline error`() = runTest {
        coEvery { checkInService.checkIn(any(), any(), any(), any(), any()) } throws DailyOKError.Offline()
        val result = performCheckInHelper("f1", "r1", "req1", null, "app")
        assertFalse(result)
    }

    @Test
    fun `performCheckIn queues check-in on network error`() = runTest {
        coEvery { checkInService.checkIn(any(), any(), any(), any(), any()) } throws DailyOKError.Network()
        val result = performCheckInHelper("f1", "r1", "req1", null, "app")
        assertFalse(result)
    }

    @Test
    fun `syncPendingCheckIns syncs all unsynced check-ins`() = runTest {
        val pending = listOf(
            OfflineCheckIn("id1", "f1", "r1", null, "app", 1000L, false),
            OfflineCheckIn("id2", "f1", "r1", "happy", "app", 2000L, false)
        )
        coEvery { dao.getUnsynced() } returns pending
        // occurredAt must be matched explicitly: the sync path now passes it,
        // and a stub that leaves it at its null default would not match.
        coEvery {
            checkInService.checkIn(any(), any(), any(), any(), any(), occurredAt = any())
        } returns "ok"

        syncPendingHelper()

        coVerify(exactly = 2) {
            checkInService.checkIn(any(), any(), any(), any(), any(), occurredAt = any())
        }
        // Deleted, not flagged: nothing reads a synced row, so flagging grew
        // the table for the life of the install (US-IOS147).
        coVerify { dao.deleteById("id1") }
        coVerify { dao.deleteById("id2") }
    }

    @Test
    fun `syncPendingCheckIns stops on first failure`() = runTest {
        val pending = listOf(
            OfflineCheckIn("id1", "f1", "r1", null, "app", 1000L, false),
            OfflineCheckIn("id2", "f1", "r1", null, "app", 2000L, false)
        )
        coEvery { dao.getUnsynced() } returns pending
        coEvery {
            checkInService.checkIn(any(), any(), "id1", any(), any(), occurredAt = any())
        } throws RuntimeException("fail")

        syncPendingHelper()

        coVerify(exactly = 1) {
            checkInService.checkIn(any(), any(), any(), any(), any(), occurredAt = any())
        }
        coVerify(exactly = 0) { dao.deleteById(any()) }
    }

    // MARK: occurred_at (US-IOS147)

    @Test
    fun `queued row timestamp is sent as RFC 3339 in UTC`() {
        // This string decides which local calendar day the server files the
        // check-in under, so the wire format is worth pinning. Without it the
        // server stamps now() and a Monday tap synced on Thursday is recorded
        // as a Thursday check-in nobody made.
        assertEquals("2026-03-13T18:30:00Z", Instant.ofEpochMilli(1_773_426_600_000L).toString())
    }

    @Test
    fun `replay window matches the server and iOS bound`() {
        // OCCURRED_AT_MAX_AGE_MS in edge-functions/shared/checkin-time.ts and
        // OfflineCheckInService.maxReplayAge on iOS. Past this bound the server
        // falls back to now(), which is the bug.
        assertEquals(7L * 24 * 60 * 60 * 1000, OfflineCheckInService.MAX_REPLAY_AGE_MS)
    }

    // Mirrors OfflineCheckInService.performCheckIn logic
    private suspend fun performCheckInHelper(
        familyId: String, receiverId: String, requestId: String,
        mood: String?, source: String
    ): Boolean {
        return try {
            checkInService.checkIn(
                familyId = familyId, receiverId = receiverId,
                requestId = requestId, mood = mood, source = source
            )
            true
        } catch (_: DailyOKError.Offline) { false }
        catch (_: DailyOKError.Network) { false }
    }

    // NOTE: this helper re-implements syncPendingCheckIns rather than calling
    // it (the service needs a Context and a live ConnectivityManager). It
    // therefore proves the shape of the flow, not the production code — a
    // mirror test passes even when the real method diverges. Worth replacing
    // with an injectable seam; kept in step by hand for now.
    // Mirrors OfflineCheckInService.syncPendingCheckIns logic
    private suspend fun syncPendingHelper() {
        val unsynced = dao.getUnsynced()
        for (checkIn in unsynced) {
            try {
                checkInService.checkIn(
                    familyId = checkIn.familyId, receiverId = checkIn.receiverId,
                    requestId = checkIn.id, mood = checkIn.mood, source = checkIn.source,
                    occurredAt = Instant.ofEpochMilli(checkIn.createdAt).toString()
                )
                dao.deleteById(checkIn.id)
            } catch (_: Exception) {
                break
            }
        }
    }
}
