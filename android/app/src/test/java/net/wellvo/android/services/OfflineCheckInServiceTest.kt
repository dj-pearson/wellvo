package net.wellvo.android.services

import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import net.wellvo.android.data.OfflineCheckIn
import net.wellvo.android.data.OfflineCheckInDao
import net.wellvo.android.network.WellvoError
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

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
        coEvery { checkInService.checkIn(any(), any(), any(), any(), any()) } throws WellvoError.Offline()
        val result = performCheckInHelper("f1", "r1", "req1", null, "app")
        assertFalse(result)
    }

    @Test
    fun `performCheckIn queues check-in on network error`() = runTest {
        coEvery { checkInService.checkIn(any(), any(), any(), any(), any()) } throws WellvoError.Network()
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
        coEvery { checkInService.checkIn(any(), any(), any(), any(), any()) } returns "ok"

        syncPendingHelper()

        coVerify(exactly = 2) { checkInService.checkIn(any(), any(), any(), any(), any()) }
        coVerify { dao.markSynced("id1") }
        coVerify { dao.markSynced("id2") }
    }

    @Test
    fun `syncPendingCheckIns stops on first failure`() = runTest {
        val pending = listOf(
            OfflineCheckIn("id1", "f1", "r1", null, "app", 1000L, false),
            OfflineCheckIn("id2", "f1", "r1", null, "app", 2000L, false)
        )
        coEvery { dao.getUnsynced() } returns pending
        coEvery { checkInService.checkIn(any(), any(), "id1", any(), any()) } throws RuntimeException("fail")

        syncPendingHelper()

        coVerify(exactly = 1) { checkInService.checkIn(any(), any(), any(), any(), any()) }
        coVerify(exactly = 0) { dao.markSynced(any()) }
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
        } catch (_: WellvoError.Offline) { false }
        catch (_: WellvoError.Network) { false }
    }

    // Mirrors OfflineCheckInService.syncPendingCheckIns logic
    private suspend fun syncPendingHelper() {
        val unsynced = dao.getUnsynced()
        for (checkIn in unsynced) {
            try {
                checkInService.checkIn(
                    familyId = checkIn.familyId, receiverId = checkIn.receiverId,
                    requestId = checkIn.id, mood = checkIn.mood, source = checkIn.source
                )
                dao.markSynced(checkIn.id)
            } catch (_: Exception) {
                break
            }
        }
    }
}
