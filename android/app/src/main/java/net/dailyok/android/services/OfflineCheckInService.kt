package net.dailyok.android.services

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
import net.dailyok.android.data.OfflineCheckIn
import net.dailyok.android.data.OfflineCheckInDao
import net.dailyok.android.network.DailyOKError
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
        requestId: String? = null,
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
        } catch (e: DailyOKError.Offline) {
            queueCheckIn(familyId, receiverId, mood, source)
            false
        } catch (e: DailyOKError.Network) {
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
                // Intentionally pass requestId=null — the local row's UUID
                // doesn't match any checkin_requests row on the server, so
                // letting the edge function look up (or skip) via
                // receiver_id + family_id is the correct path.
                checkInService.checkIn(
                    familyId = checkIn.familyId,
                    receiverId = checkIn.receiverId,
                    requestId = null,
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
