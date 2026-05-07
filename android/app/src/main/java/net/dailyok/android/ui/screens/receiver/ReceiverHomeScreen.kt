package net.dailyok.android.ui.screens.receiver

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
import androidx.compose.foundation.layout.Box as LayoutBox
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.ExitToApp
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.sp
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.hilt.navigation.compose.hiltViewModel
import net.dailyok.android.R
import net.dailyok.android.ui.components.AmbientBackground
import net.dailyok.android.ui.components.AmbientTone
import net.dailyok.android.ui.components.CelebrationOverlay
import net.dailyok.android.ui.components.GlassCard
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKGlass
import net.dailyok.android.ui.theme.DailyOKGlassStyle
import net.dailyok.android.ui.theme.DailyOKGreen300
import net.dailyok.android.ui.theme.DailyOKGreen400
import net.dailyok.android.ui.theme.DailyOKGreen600
import net.dailyok.android.ui.theme.DailyOKTeal
import net.dailyok.android.ui.theme.WarningOrange
import net.dailyok.android.data.models.Mood
import net.dailyok.android.data.models.displayName
import net.dailyok.android.data.models.emoji
import net.dailyok.android.services.OfflineCheckInService
import net.dailyok.android.viewmodels.AuthViewModel
import net.dailyok.android.viewmodels.ReceiverViewModel

@Composable
fun ReceiverHomeScreen(
    viewModel: ReceiverViewModel = hiltViewModel(),
    authViewModel: AuthViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val haptic = LocalHapticFeedback.current
    val view = LocalView.current
    val context = LocalContext.current
    val isOffline by viewModel.isOffline.collectAsState()
    val pendingOfflineCount by viewModel.pendingOfflineCount.collectAsState()
    var menuExpanded by remember { mutableStateOf(false) }
    var showSignOutConfirmation by remember { mutableStateOf(false) }
    var showCelebration by remember { mutableStateOf(false) }

    // Track previous state to detect transitions
    var wasCheckedIn by remember { mutableStateOf(state.hasCheckedInToday) }
    var hadError by remember { mutableStateOf(state.errorMessage != null) }

    // Success haptic + celebration — fires when check-in completes
    LaunchedEffect(state.hasCheckedInToday) {
        if (state.hasCheckedInToday && !wasCheckedIn) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                view.performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM)
            } else {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            }
            // Only celebrate on confirmed online success (not offline-queued, no error)
            if (state.errorMessage == null && !isOffline) {
                showCelebration = true
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

    LayoutBox(modifier = Modifier.fillMaxSize()) {
    AmbientBackground(tone = if (state.hasCheckedInToday) AmbientTone.Calm else AmbientTone.Warm)
    Column(modifier = Modifier.fillMaxSize()) {
        // Offline banner
        if (isOffline) {
            GlassCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                style = DailyOKGlassStyle.Thin,
                shape = RoundedCornerShape(DailyOKGlass.RadiusMedium),
                elevation = DailyOKElevation.level2,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp)
            ) {
                Text(
                    text = stringResource(R.string.receiver_offline_banner),
                    style = MaterialTheme.typography.bodySmall,
                    color = WarningOrange
                )
            }
        }

        if (pendingOfflineCount > 0) {
            GlassCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                style = DailyOKGlassStyle.Thin,
                shape = RoundedCornerShape(DailyOKGlass.RadiusMedium),
                elevation = DailyOKElevation.level2,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp)
            ) {
                Text(
                    text = stringResource(R.string.receiver_pending_sync, pendingOfflineCount),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        // Streak + 7-day consistency header. Both chips self-hide when there
        // isn't enough history (streak < 2, consistency < 50%), so the row is
        // empty for first-day receivers.
        run {
            val consistencyBadge = net.dailyok.android.util.Streaks.badge(state.consistencyPercent)
            if (state.streakDays >= 2 || consistencyBadge != net.dailyok.android.util.ConsistencyBadge.None) {
                androidx.compose.foundation.layout.Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    net.dailyok.android.ui.components.StreakChip(streakDays = state.streakDays)
                    net.dailyok.android.ui.components.ConsistencyChip(badge = consistencyBadge)
                }
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

        // Discreet top-right menu — sign out + link into Android app
        // notification settings. Overlay so it's reachable from either the
        // check-in button state or the "all set" state.
        IconButton(
            onClick = { menuExpanded = true },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(8.dp)
        ) {
            Icon(
                imageVector = Icons.Default.MoreVert,
                contentDescription = "More options",
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        DropdownMenu(
            expanded = menuExpanded,
            onDismissRequest = { menuExpanded = false },
            modifier = Modifier.align(Alignment.TopEnd)
        ) {
            DropdownMenuItem(
                text = { Text("Notification Settings") },
                leadingIcon = { Icon(Icons.Default.Notifications, contentDescription = null) },
                onClick = {
                    menuExpanded = false
                    val intent = android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
                    }
                    context.startActivity(intent)
                }
            )
            DropdownMenuItem(
                text = { Text("Sign Out") },
                leadingIcon = { Icon(Icons.Default.ExitToApp, contentDescription = null) },
                onClick = {
                    menuExpanded = false
                    showSignOutConfirmation = true
                }
            )
        }

        CelebrationOverlay(
            visible = showCelebration,
            onComplete = { showCelebration = false }
        )
    }

    if (showSignOutConfirmation) {
        val dailyokHaptics = net.dailyok.android.ui.theme.rememberDailyOKHaptics()
        net.dailyok.android.ui.components.GlassAlertDialog(
            onDismissRequest = { showSignOutConfirmation = false },
            title = { Text("Sign Out") },
            text = { Text("You'll stop receiving check-in notifications until you sign back in.") },
            confirmButton = {
                TextButton(onClick = {
                    dailyokHaptics.warning()
                    showSignOutConfirmation = false
                    authViewModel.signOut()
                }) { Text("Sign Out") }
            },
            dismissButton = {
                TextButton(onClick = { showSignOutConfirmation = false }) { Text("Cancel") }
            }
        )
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
    // Slow breathing pulse
    val transition = rememberInfiniteTransition(label = "pulse")
    val pulse by transition.animateFloat(
        initialValue = 1.0f,
        targetValue = 1.06f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 2000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseAnim"
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.padding(24.dp)
    ) {
        LayoutBox(contentAlignment = Alignment.Center) {
            // Aurora halo — soft blurred orbs that breathe with the pulse
            LayoutBox(
                modifier = Modifier
                    .size(280.dp)
                    .scale(pulse)
                    .background(
                        brush = Brush.radialGradient(
                            listOf(DailyOKGreen300.copy(alpha = 0.55f), Color.Transparent),
                        ),
                        shape = CircleShape
                    )
            )
            LayoutBox(
                modifier = Modifier
                    .size(240.dp)
                    .scale(pulse)
                    .background(
                        brush = Brush.radialGradient(
                            listOf(DailyOKTeal.copy(alpha = 0.4f), Color.Transparent),
                        ),
                        shape = CircleShape
                    )
            )

            // Main button with brand gradient + specular highlight + hairline stroke
            Button(
                onClick = onCheckIn,
                modifier = Modifier
                    .size(200.dp)
                    .shadow(
                        elevation = 24.dp,
                        shape = CircleShape,
                        ambientColor = DailyOKGreen600.copy(alpha = 0.45f),
                        spotColor = DailyOKGreen600.copy(alpha = 0.45f)
                    )
                    .clip(CircleShape)
                    .background(
                        Brush.linearGradient(listOf(DailyOKGreen400, DailyOKGreen600))
                    )
                    .background(
                        brush = Brush.verticalGradient(
                            listOf(Color.White.copy(alpha = 0.35f), Color.Transparent)
                        ),
                        shape = CircleShape
                    )
                    .border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape),
                shape = CircleShape,
                enabled = !isCheckingIn,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.Transparent,
                    disabledContainerColor = Color.Transparent
                ),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)
            ) {
                if (isCheckingIn) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(48.dp),
                        color = Color.White,
                        strokeWidth = 4.dp
                    )
                } else {
                    Text(
                        text = stringResource(R.string.receiver_im_ok),
                        style = MaterialTheme.typography.headlineLarge.copy(
                            fontSize = 32.sp,
                            fontWeight = FontWeight.Bold
                        ),
                        color = Color.White
                    )
                }
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
                Text(stringResource(R.string.receiver_dismiss))
            }
        }

        nextCheckInTime?.let {
            Spacer(modifier = Modifier.height(32.dp))
            Text(
                text = stringResource(R.string.receiver_next_checkin),
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
            text = stringResource(R.string.receiver_all_set),
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(16.dp))

        GlassCard(
            modifier = Modifier.fillMaxWidth(),
            style = DailyOKGlassStyle.Regular,
            shape = RoundedCornerShape(DailyOKGlass.RadiusLarge),
            elevation = DailyOKElevation.level3,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = stringResource(R.string.receiver_checked_in_today),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )
                checkInTime?.let {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface
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
                text = stringResource(R.string.receiver_next_checkin),
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
            Text(stringResource(R.string.receiver_retry))
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
