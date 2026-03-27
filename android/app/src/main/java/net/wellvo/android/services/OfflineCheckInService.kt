package net.wellvo.android.services

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import net.wellvo.android.data.OfflineCheckIn
import net.wellvo.android.data.OfflineCheckInDao
import net.wellvo.android.network.WellvoError
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OfflineCheckInService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val offlineCheckInDao: OfflineCheckInDao,
    private val checkInService: CheckInService
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _isOffline = MutableStateFlow(false)
    val isOffline: StateFlow<Boolean> = _isOffline.asStateFlow()

    private val _pendingOfflineCount = MutableStateFlow(0)
    val pendingOfflineCount: StateFlow<Int> = _pendingOfflineCount.asStateFlow()

    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            _isOffline.value = false
            scope.launch { syncPendingCheckIns() }
        }

        override fun onLost(network: Network) {
            _isOffline.value = !hasNetworkConnectivity()
        }

        override fun onCapabilitiesChanged(
            network: Network,
            capabilities: NetworkCapabilities
        ) {
            val hasInternet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            _isOffline.value = !hasInternet
        }
    }

    init {
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        connectivityManager.registerNetworkCallback(request, networkCallback)
        _isOffline.value = !hasNetworkConnectivity()
        scope.launch { refreshPendingCount() }
    }

    private fun hasNetworkConnectivity(): Boolean {
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    suspend fun performCheckIn(
        familyId: String,
        receiverId: String,
        requestId: String,
        mood: String? = null,
        source: String = "app"
    ): Boolean {
        return try {
            checkInService.checkIn(
                familyId = familyId,
                receiverId = receiverId,
                requestId = requestId,
                mood = mood,
                source = source
            )
            true
        } catch (e: WellvoError.Offline) {
            queueCheckIn(familyId, receiverId, mood, source)
            false
        } catch (e: WellvoError.Network) {
            queueCheckIn(familyId, receiverId, mood, source)
            false
        }
    }

    private suspend fun queueCheckIn(
        familyId: String,
        receiverId: String,
        mood: String?,
        source: String
    ) {
        val offlineCheckIn = OfflineCheckIn(
            id = UUID.randomUUID().toString(),
            familyId = familyId,
            receiverId = receiverId,
            mood = mood,
            source = source,
            createdAt = System.currentTimeMillis(),
            synced = false
        )
        offlineCheckInDao.insert(offlineCheckIn)
        refreshPendingCount()
    }

    suspend fun syncPendingCheckIns() {
        val unsynced = offlineCheckInDao.getUnsynced()
        for (checkIn in unsynced) {
            try {
                checkInService.checkIn(
                    familyId = checkIn.familyId,
                    receiverId = checkIn.receiverId,
                    requestId = checkIn.id,
                    mood = checkIn.mood,
                    source = checkIn.source
                )
                offlineCheckInDao.markSynced(checkIn.id)
            } catch (_: Exception) {
                // Will retry on next sync
                break
            }
        }
        refreshPendingCount()
    }

    private suspend fun refreshPendingCount() {
        _pendingOfflineCount.value = offlineCheckInDao.getUnsynced().size
    }
}
