package net.wellvo.android.services

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import net.wellvo.android.network.ApiService
import net.wellvo.android.network.ReportLocationRequest
import net.wellvo.android.util.SecureStorage
import java.util.concurrent.TimeUnit

@HiltWorker
class LocationReportWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val locationService: LocationService,
    private val apiService: ApiService,
    private val secureStorage: SecureStorage
) : CoroutineWorker(context, workerParams) {

    companion object {
        private const val TAG = "LocationReportWorker"
        private const val WORK_NAME = "wellvo_location_report"
        const val KEY_FAMILY_ID = "family_id"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<LocationReportWorker>(
                15, TimeUnit.MINUTES
            ).build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
            Log.d(TAG, "Location report worker scheduled")
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.d(TAG, "Location report worker cancelled")
        }
    }

    override suspend fun doWork(): Result {
        if (!locationService.hasBackgroundLocationPermission()) {
            Log.w(TAG, "No background location permission, skipping")
            return Result.success()
        }

        val familyId = inputData.getString(KEY_FAMILY_ID)
            ?: secureStorage.load("family_id")
        if (familyId == null) {
            Log.w(TAG, "No family ID available, skipping location report")
            return Result.success()
        }

        return try {
            val location = locationService.getCurrentLocation()
            if (location != null) {
                apiService.reportLocation(
                    ReportLocationRequest(
                        familyId = familyId,
                        latitude = location.latitude,
                        longitude = location.longitude,
                        accuracyMeters = location.accuracyMeters
                    )
                )
                Log.d(TAG, "Location reported successfully")
            } else {
                Log.w(TAG, "Could not get location")
            }
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to report location", e)
            Result.retry()
        }
    }
}
