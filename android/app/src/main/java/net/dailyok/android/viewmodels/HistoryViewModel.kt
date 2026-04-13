package net.dailyok.android.viewmodels

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.dailyok.android.data.models.CheckIn
import net.dailyok.android.data.models.MemberStatus
import net.dailyok.android.data.models.UserRole
import net.dailyok.android.services.AnalyticsService
import net.dailyok.android.services.CheckInService
import net.dailyok.android.services.FamilyService
import androidx.compose.runtime.Immutable
import javax.inject.Inject

@Immutable
data class ReceiverOption(
    val id: String,
    val name: String
)

@HiltViewModel
class HistoryViewModel @Inject constructor(
    private val checkInService: CheckInService,
    private val familyService: FamilyService,
    private val analyticsService: AnalyticsService
) : ViewModel() {

    private val _receivers = MutableStateFlow<List<ReceiverOption>>(emptyList())
    val receivers: StateFlow<List<ReceiverOption>> = _receivers.asStateFlow()

    private val _selectedReceiverId = MutableStateFlow<String?>(null)
    val selectedReceiverId: StateFlow<String?> = _selectedReceiverId.asStateFlow()

    private val _selectedPeriod = MutableStateFlow(7)
    val selectedPeriod: StateFlow<Int> = _selectedPeriod.asStateFlow()

    private val _checkIns = MutableStateFlow<List<CheckIn>>(emptyList())
    val checkIns: StateFlow<List<CheckIn>> = _checkIns.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _isExporting = MutableStateFlow(false)
    val isExporting: StateFlow<Boolean> = _isExporting.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    private val _hasMorePages = MutableStateFlow(true)
    val hasMorePages: StateFlow<Boolean> = _hasMorePages.asStateFlow()

    private var familyId: String? = null
    private var familyName: String? = null
    private var currentOffset = 0

    companion object {
        private const val PAGE_SIZE = 20
    }

    fun initialize(userId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            analyticsService.track(AnalyticsService.HISTORY_VIEWED)
            try {
                val family = familyService.getFamily(userId) ?: run {
                    _isLoading.value = false
                    return@launch
                }
                familyId = family.id
                familyName = family.name

                val members = familyService.getFamilyMembers(family.id)
                val receiverList = members
                    .filter { it.role == UserRole.Receiver && it.status == MemberStatus.Active }
                    .map { ReceiverOption(id = it.userId, name = it.user?.displayName ?: "Unknown") }

                _receivers.value = receiverList

                if (receiverList.isNotEmpty() && _selectedReceiverId.value == null) {
                    _selectedReceiverId.value = receiverList.first().id
                }

                loadHistory()
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to load receivers."
            }
            _isLoading.value = false
        }
    }

    fun selectReceiver(receiverId: String) {
        _selectedReceiverId.value = receiverId
        loadHistory()
    }

    fun selectPeriod(days: Int) {
        _selectedPeriod.value = days
        loadHistory()
    }

    private fun loadHistory() {
        val recId = _selectedReceiverId.value ?: return
        val famId = familyId ?: return
        val days = _selectedPeriod.value

        currentOffset = 0
        _hasMorePages.value = true

        viewModelScope.launch {
            _isLoading.value = true
            try {
                val history = checkInService.checkInHistoryPaginated(
                    receiverId = recId,
                    familyId = famId,
                    days = days,
                    limit = PAGE_SIZE,
                    offset = 0
                )
                _checkIns.value = history
                currentOffset = history.size
                _hasMorePages.value = history.size >= PAGE_SIZE
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to load history."
                _checkIns.value = emptyList()
            }
            _isLoading.value = false
        }
    }

    fun loadMore() {
        if (_isLoadingMore.value || !_hasMorePages.value) return
        val recId = _selectedReceiverId.value ?: return
        val famId = familyId ?: return
        val days = _selectedPeriod.value

        viewModelScope.launch {
            _isLoadingMore.value = true
            try {
                val moreHistory = checkInService.checkInHistoryPaginated(
                    receiverId = recId,
                    familyId = famId,
                    days = days,
                    limit = PAGE_SIZE,
                    offset = currentOffset
                )
                _checkIns.value = _checkIns.value + moreHistory
                currentOffset += moreHistory.size
                _hasMorePages.value = moreHistory.size >= PAGE_SIZE
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to load more history."
            }
            _isLoadingMore.value = false
        }
    }

    fun exportPdf(context: Context, onComplete: (Intent) -> Unit) {
        val recId = _selectedReceiverId.value ?: return
        val famId = familyId ?: return
        val receiverName = _receivers.value.find { it.id == recId }?.name ?: "Receiver"
        val fName = familyName ?: "Family"
        val days = _selectedPeriod.value
        val currentCheckIns = _checkIns.value

        viewModelScope.launch {
            _isExporting.value = true
            try {
                val file = withContext(Dispatchers.IO) {
                    net.dailyok.android.services.PdfExportService.export(
                        context = context,
                        familyName = fName,
                        receiverName = receiverName,
                        days = days,
                        checkIns = currentCheckIns
                    )
                }
                val uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    file
                )
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "application/pdf"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_SUBJECT, "Daily OK Check-in Report - $receiverName")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                onComplete(Intent.createChooser(shareIntent, "Share PDF Report"))
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to export PDF."
            }
            _isExporting.value = false
        }
    }

    fun clearError() { _errorMessage.value = null }
}
