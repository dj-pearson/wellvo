package net.wellvo.android.ui.screens.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import net.wellvo.android.viewmodels.ReceiverOnboardingViewModel

@Composable
fun ReceiverOnboardingScreen(
    inviteToken: String?,
    onComplete: () -> Unit = {},
    viewModel: ReceiverOnboardingViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsState()

    LaunchedEffect(inviteToken) {
        if (inviteToken != null) {
            viewModel.acceptInvite(inviteToken)
        } else {
            viewModel.loadReceiverSettings()
        }
    }

    if (state.isComplete) {
        onComplete()
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.weight(1f))

        when (state.currentStep) {
            0 -> WelcomeStep(
                receiverName = state.receiverName,
                checkinTime = state.checkinTime,
                isLoading = state.isLoading,
                errorMessage = state.errorMessage,
                onContinue = viewModel::advance
            )
            1 -> NotificationsStep(
                onPermissionResult = viewModel::onNotificationPermissionResult
            )
            2 -> CompleteStep(
                notificationDenied = state.notificationDenied,
                onStart = {
                    viewModel.markComplete()
                    onComplete()
                }
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        // Progress dots
        ProgressDots(
            currentStep = state.currentStep,
            totalSteps = 3
        )

        Spacer(modifier = Modifier.height(32.dp))
    }
}

@Composable
private fun ProgressDots(currentStep: Int, totalSteps: Int) {
    Row(
        horizontalArrangement = Arrangement.Center,
        modifier = Modifier.fillMaxWidth()
    ) {
        repeat(totalSteps) { index ->
            Box(
                modifier = Modifier
                    .size(if (index == currentStep) 10.dp else 8.dp)
                    .clip(CircleShape)
                    .background(
                        if (index == currentStep) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.outlineVariant
                    )
            )
            if (index < totalSteps - 1) {
                Spacer(modifier = Modifier.width(8.dp))
            }
        }
    }
}

@Composable
private fun WelcomeStep(
    receiverName: String,
    checkinTime: String?,
    isLoading: Boolean,
    errorMessage: String?,
    onContinue: () -> Unit
) {
    if (isLoading) {
        CircularProgressIndicator()
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "Setting up your account...",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        return
    }

    Icon(
        imageVector = Icons.Default.Favorite,
        contentDescription = null,
        modifier = Modifier.size(80.dp),
        tint = MaterialTheme.colorScheme.primary
    )

    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = if (receiverName.isNotBlank()) "Welcome, $receiverName!" else "Welcome!",
        style = MaterialTheme.typography.headlineLarge,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "Someone who cares about you has set up a daily check-in. Each day, you'll get a notification — just tap \"I'm OK\" to let them know you're doing well.",
        style = MaterialTheme.typography.bodyLarge,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    if (checkinTime != null) {
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = "Your daily check-in is at",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = checkinTime,
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.primary
        )
    }

    errorMessage?.let {
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = it,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall
        )
    }

    Spacer(modifier = Modifier.height(48.dp))

    Button(
        onClick = onContinue,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text("Continue")
    }
}

@Composable
private fun NotificationsStep(
    onPermissionResult: (Boolean) -> Unit
) {
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        onPermissionResult(granted)
    }

    Icon(
        imageVector = Icons.Default.Notifications,
        contentDescription = null,
        modifier = Modifier.size(80.dp),
        tint = MaterialTheme.colorScheme.primary
    )

    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = "Don't miss your check-in",
        style = MaterialTheme.typography.headlineMedium,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "Notifications are how we remind you to check in each day. Without them, you might miss your check-in and your family will worry.",
        style = MaterialTheme.typography.bodyLarge,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    Spacer(modifier = Modifier.height(48.dp))

    Button(
        onClick = {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                onPermissionResult(true)
            }
        },
        modifier = Modifier.fillMaxWidth()
    ) {
        Text("Enable Notifications")
    }

    Spacer(modifier = Modifier.height(8.dp))

    TextButton(
        onClick = { onPermissionResult(false) },
        modifier = Modifier.fillMaxWidth()
    ) {
        Text("Not now")
    }
}

@Composable
private fun CompleteStep(
    notificationDenied: Boolean,
    onStart: () -> Unit
) {
    Icon(
        imageVector = Icons.Default.CheckCircle,
        contentDescription = null,
        modifier = Modifier.size(80.dp),
        tint = MaterialTheme.colorScheme.primary
    )

    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = "You're all set!",
        style = MaterialTheme.typography.headlineLarge,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "When it's time for your daily check-in, just open the app and tap the button. It takes one second.",
        style = MaterialTheme.typography.bodyLarge,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    if (notificationDenied) {
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "You can enable notifications later in Settings to get check-in reminders.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.tertiary
        )
    }

    Spacer(modifier = Modifier.height(48.dp))

    Button(
        onClick = onStart,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text("Start Using Wellvo")
    }
}
