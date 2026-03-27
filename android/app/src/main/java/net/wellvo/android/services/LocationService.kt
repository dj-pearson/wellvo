package net.wellvo.android.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import javax.inject.Inject
import javax.inject.Singleton

data class WellvoLocation(
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Double
)

@Singleton
class LocationService @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val TAG = "LocationService"
        private const val LOCATION_TIMEOUT_MS = 10_000L

        val FOREGROUND_PERMISSIONS = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )

        val BACKGROUND_PERMISSION = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Manifest.permission.ACCESS_BACKGROUND_LOCATION
        } else null
    }

    private val fusedLocationClient: FusedLocationProviderClient by lazy {
        LocationServices.getFusedLocationProviderClient(context)
    }

    fun hasFineLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun hasCoarseLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun hasAnyLocationPermission(): Boolean {
        return hasFineLocationPermission() || hasCoarseLocationPermission()
    }

    fun isLocationGranted(): Boolean = hasAnyLocationPermission()

    fun isBackgroundLocationGranted(): Boolean = hasBackgroundLocationPermission()

    fun hasBackgroundLocationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            hasAnyLocationPermission()
        }
    }

    fun requiresBackgroundPermissionRequest(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    }

    @Suppress("MissingPermission")
    suspend fun getCurrentLocation(): WellvoLocation? {
        if (!hasAnyLocationPermission()) {
            Log.w(TAG, "No location permission")
            return null
        }

        return try {
            withTimeoutOrNull(LOCATION_TIMEOUT_MS) {
                val priority = if (hasFineLocationPermission()) {
                    Priority.PRIORITY_HIGH_ACCURACY
                } else {
                    Priority.PRIORITY_BALANCED_POWER_ACCURACY
                }
                val cancellationToken = CancellationTokenSource()
                val location = fusedLocationClient
                    .getCurrentLocation(priority, cancellationToken.token)
                    .await()

                if (location != null) {
                    WellvoLocation(
                        latitude = location.latitude,
                        longitude = location.longitude,
                        accuracyMeters = location.accuracy.toDouble()
                    )
                } else {
                    getLastKnownLocation()
                }
            } ?: run {
                Log.w(TAG, "Location request timed out after ${LOCATION_TIMEOUT_MS}ms")
                getLastKnownLocation()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get current location", e)
            getLastKnownLocation()
        }
    }

    @Suppress("MissingPermission")
    suspend fun getLastKnownLocation(): WellvoLocation? {
        if (!hasAnyLocationPermission()) return null

        return try {
            val location = fusedLocationClient.lastLocation.await()
            location?.let {
                WellvoLocation(
                    latitude = it.latitude,
                    longitude = it.longitude,
                    accuracyMeters = it.accuracy.toDouble()
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get last known location", e)
            null
        }
    }
}
