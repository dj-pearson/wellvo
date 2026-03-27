package net.wellvo.android.ui.screens.receiver

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import net.wellvo.android.data.models.Mood
import net.wellvo.android.data.models.displayName
import net.wellvo.android.data.models.emoji
import net.wellvo.android.services.OfflineCheckInService
import net.wellvo.android.viewmodels.ReceiverViewModel

@Composable
fun ReceiverHomeScreen(
    viewModel: ReceiverViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val haptic = LocalHapticFeedback.current
    val view = LocalView.current
    val isOffline by viewModel.isOffline.collectAsState()
    val pendingOfflineCount by viewModel.pendingOfflineCount.collectAsState()

    // Track previous state to detect transitions
    var wasCheckedIn by remember { mutableStateOf(state.hasCheckedInToday) }
    var hadError by remember { mutableStateOf(state.errorMessage != null) }

    // Success haptic — fires when check-in completes
    LaunchedEffect(state.hasCheckedInToday) {
        if (state.hasCheckedInToday && !wasCheckedIn) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                view.performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM)
            } else {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            }
        }
        wasCheckedIn = state.hasCheckedInToday
    }

    // Error haptic — fires when an error appears
    LaunchedEffect(state.errorMessage) {
        if (state.errorMessage != null && !hadError) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                view.performHapticFeedback(android.view.HapticFeedbackConstants.REJECT)
            } else {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            }
        }
        hadError = state.errorMessage != null
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Offline banner
        if (isOffline) {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                )
            ) {
                Text(
                    text = "You're offline. Check-ins will be saved and synced later.",
                    modifier = Modifier.padding(12.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onErrorContainer
                )
            }
        }

        if (pendingOfflineCount > 0) {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.tertiaryContainer
                )
            ) {
                Text(
                    text = "$pendingOfflineCount check-in${if (pendingOfflineCount > 1) "s" else ""} pending sync",
                    modifier = Modifier.padding(12.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onTertiaryContainer
                )
            }
        }

        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
        when {
            state.isLoading -> {
                CircularProgressIndicator()
            }
            state.errorMessage != null && !state.hasCheckedInToday -> {
                ErrorState(
                    message = state.errorMessage!!,
                    onRetry = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        viewModel.retry()
                    }
                )
            }
            state.hasCheckedInToday -> {
                CheckedInState(
                    checkInTime = state.lastCheckIn?.checkedInAt?.let { formatCheckInTime(it) },
                    mood = state.lastCheckIn?.mood,
                    showMoodSelector = state.showMoodSelector,
                    isKidMode = state.isKidMode,
                    selectedMood = state.selectedMood,
                    onSelectMood = viewModel::selectMood,
                    onSubmitMood = viewModel::submitMood,
                    onSkipMood = viewModel::skipMood,
                    showLocationSelector = state.showLocationSelector,
                    selectedLocationLabel = state.selectedLocationLabel,
                    onSelectLocation = viewModel::selectLocationLabel,
                    onSubmitLocation = viewModel::submitLocationLabel,
                    onSkipLocation = viewModel::skipLocationLabel,
                    showKidResponseButtons = state.showKidResponseButtons,
                    selectedKidResponse = state.selectedKidResponse,
                    onSelectKidResponse = viewModel::selectKidResponse,
                    onSubmitKidResponse = viewModel::submitKidResponse,
                    onSkipKidResponse = viewModel::skipKidResponse,
                    nextCheckInTime = state.nextCheckInTime
                )
            }
            else -> {
                CheckInButton(
                    isCheckingIn = state.isCheckingIn,
                    errorMessage = state.errorMessage,
                    nextCheckInTime = state.nextCheckInTime,
                    onCheckIn = {
                        viewModel.checkIn()
                        haptic.performHapticFeedback(HapticFeedbackType.Companion.LongPress)
                    },
                    onClearError = viewModel::clearError
                )
            }
        }
        }
    }
}

@Composable
private fun CheckInButton(
    isCheckingIn: Boolean,
    errorMessage: String?,
    nextCheckInTime: String?,
    onCheckIn: () -> Unit,
    onClearError: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.padding(24.dp)
    ) {
        Button(
            onClick = onCheckIn,
            modifier = Modifier.size(200.dp),
            shape = CircleShape,
            enabled = !isCheckingIn,
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary
            )
        ) {
            if (isCheckingIn) {
                CircularProgressIndicator(
                    modifier = Modifier.size(48.dp),
                    color = MaterialTheme.colorScheme.onPrimary,
                    strokeWidth = 4.dp
                )
            } else {
                Text(
                    text = "I'm OK",
                    style = MaterialTheme.typography.headlineLarge.copy(
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold
                    ),
                    color = MaterialTheme.colorScheme.onPrimary
                )
            }
        }

        errorMessage?.let {
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = it,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(8.dp))
            TextButton(onClick = onClearError) {
                Text("Dismiss")
            }
        }

        nextCheckInTime?.let {
            Spacer(modifier = Modifier.height(32.dp))
            Text(
                text = "Next check-in at",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = it,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@Composable
private fun CheckedInState(
    checkInTime: String?,
    mood: Mood?,
    showMoodSelector: Boolean,
    isKidMode: Boolean,
    selectedMood: Mood?,
    onSelectMood: (Mood) -> Unit,
    onSubmitMood: () -> Unit,
    onSkipMood: () -> Unit,
    showLocationSelector: Boolean,
    selectedLocationLabel: String?,
    onSelectLocation: (String) -> Unit,
    onSubmitLocation: () -> Unit,
    onSkipLocation: () -> Unit,
    showKidResponseButtons: Boolean,
    selectedKidResponse: String?,
    onSelectKidResponse: (String) -> Unit,
    onSubmitKidResponse: () -> Unit,
    onSkipKidResponse: () -> Unit,
    nextCheckInTime: String?
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .padding(24.dp)
            .verticalScroll(rememberScrollState())
    ) {
        AnimatedVisibility(
            visible = true,
            enter = scaleIn() + fadeIn()
        ) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = "Checked in",
                modifier = Modifier.size(80.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "You're all set!",
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(16.dp))

        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer
            )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "Checked in today",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
                checkInTime?.let {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
                mood?.let {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "${it.emoji()} ${it.displayName()}",
                        style = MaterialTheme.typography.bodyLarge
                    )
                }
            }
        }

        if (showMoodSelector) {
            Spacer(modifier = Modifier.height(24.dp))
            MoodSelector(
                isKidMode = isKidMode,
                selectedMood = selectedMood,
                onSelectMood = onSelectMood,
                onSubmit = onSubmitMood,
                onSkip = onSkipMood
            )
        }

        if (showLocationSelector) {
            Spacer(modifier = Modifier.height(24.dp))
            LocationLabelSelector(
                selectedLabel = selectedLocationLabel,
                onSelect = onSelectLocation,
                onSubmit = onSubmitLocation,
                onSkip = onSkipLocation
            )
        }

        if (showKidResponseButtons) {
            Spacer(modifier = Modifier.height(24.dp))
            KidResponseButtons(
                selectedResponse = selectedKidResponse,
                onSelect = onSelectKidResponse,
                onSubmit = onSubmitKidResponse,
                onSkip = onSkipKidResponse
            )
        }

        nextCheckInTime?.let {
            Spacer(modifier = Modifier.height(32.dp))
            Text(
                text = "Next check-in at",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = it,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@Composable
private fun ErrorState(
    message: String,
    onRetry: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.padding(24.dp)
    ) {
        Icon(
            imageVector = Icons.Default.Refresh,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.error
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.error
        )
        Spacer(modifier = Modifier.height(16.dp))
        Button(onClick = onRetry) {
            Text("Retry")
        }
    }
}

private fun formatCheckInTime(isoTimestamp: String): String {
    // Parse ISO 8601 timestamp like "2026-03-26T09:15:00+00:00"
    try {
        val timePart = isoTimestamp.substringAfter("T").take(5)
        val parts = timePart.split(":")
        val hour = parts[0].toInt()
        val minute = parts[1].toInt()
        val amPm = if (hour < 12) "AM" else "PM"
        val displayHour = when {
            hour == 0 -> 12
            hour > 12 -> hour - 12
            else -> hour
        }
        return "%d:%02d %s".format(displayHour, minute, amPm)
    } catch (_: Exception) {
        return isoTimestamp
    }
}
