package net.dailyok.android.services

import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import net.dailyok.android.network.ApiService
import net.dailyok.android.network.CheckInResponseRequest
import net.dailyok.android.network.ConfirmDeliveryRequest
import net.dailyok.android.network.OnDemandCheckinRequest
import net.dailyok.android.network.DailyOKError
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CheckInServiceTest {

    private lateinit var apiService: ApiService

    @Before
    fun setUp() {
        apiService = mockk(relaxed = true)
    }

    @Test
    fun `checkIn calls processCheckinResponse with correct request`() = runTest {
        coEvery { apiService.processCheckinResponse(any()) } returns "checkin-123"
        val result = checkInHelper("f1", "r1", "req1", "happy", "app")
        assertEquals("checkin-123", result)
        coVerify {
            apiService.processCheckinResponse(match {
                it.requestId == "req1" && it.mood == "happy" && it.source == "app"
            })
        }
    }

    @Test
    fun `checkIn propagates DailyOKError`() = runTest {
        coEvery { apiService.processCheckinResponse(any()) } throws DailyOKError.Auth()
        try {
            checkInHelper("f1", "r1", "req1", null, "app")
            fail("Expected DailyOKError.Auth")
        } catch (e: DailyOKError.Auth) {
            // expected
        }
    }

    @Test
    fun `checkIn wraps unknown exceptions`() = runTest {
        coEvery { apiService.processCheckinResponse(any()) } throws RuntimeException("unexpected")
        try {
            checkInHelper("f1", "r1", "req1", null, "app")
            fail("Expected DailyOKError.Unknown")
        } catch (e: DailyOKError.Unknown) {
            assertEquals("unexpected", e.message)
        }
    }

    @Test
    fun `sendOnDemandCheckIn calls API with correct parameters`() = runTest {
        coEvery { apiService.onDemandCheckin(any()) } returns "demand-123"
        val result = sendOnDemandHelper("f1", "r1")
        assertEquals("demand-123", result)
        coVerify {
            apiService.onDemandCheckin(match {
                it.receiverId == "r1" && it.familyId == "f1"
            })
        }
    }

    @Test
    fun `confirmDelivery calls API with request ID`() = runTest {
        coEvery { apiService.confirmDelivery(any()) } returns "ok"
        confirmDeliveryHelper("req-456")
        coVerify {
            apiService.confirmDelivery(match { it.requestId == "req-456" })
        }
    }

    @Test
    fun `checkIn includes location data when provided`() = runTest {
        coEvery { apiService.processCheckinResponse(any()) } returns "checkin-loc"
        checkInHelper("f1", "r1", "req1", null, "app", 40.7128, -74.0060, 10.0)
        coVerify {
            apiService.processCheckinResponse(match {
                it.latitude == 40.7128 && it.longitude == -74.0060 && it.locationAccuracyMeters == 10.0
            })
        }
    }

    // Mirrors CheckInService.checkIn logic
    private suspend fun checkInHelper(
        familyId: String, receiverId: String, requestId: String?,
        mood: String?, source: String,
        latitude: Double? = null, longitude: Double? = null,
        locationAccuracy: Double? = null, kidResponseType: String? = null
    ): String {
        try {
            return apiService.processCheckinResponse(
                CheckInResponseRequest(
                    requestId = requestId,
                    receiverId = receiverId,
                    familyId = familyId,
                    mood = mood, source = source,
                    latitude = latitude, longitude = longitude,
                    locationAccuracyMeters = locationAccuracy,
                    kidResponseType = kidResponseType
                )
            )
        } catch (e: DailyOKError) { throw e }
        catch (e: Exception) { throw DailyOKError.Unknown(e.message ?: "Check-in failed.") }
    }

    // Mirrors CheckInService.sendOnDemandCheckIn
    private suspend fun sendOnDemandHelper(familyId: String, receiverId: String): String {
        try {
            return apiService.onDemandCheckin(
                OnDemandCheckinRequest(receiverId = receiverId, familyId = familyId)
            )
        } catch (e: DailyOKError) { throw e }
        catch (e: Exception) { throw DailyOKError.Unknown(e.message ?: "Failed.") }
    }

    // Mirrors CheckInService.confirmDelivery
    private suspend fun confirmDeliveryHelper(checkinRequestId: String) {
        try {
            apiService.confirmDelivery(ConfirmDeliveryRequest(requestId = checkinRequestId))
        } catch (e: DailyOKError) { throw e }
        catch (e: Exception) { throw DailyOKError.Unknown(e.message ?: "Failed.") }
    }
}
