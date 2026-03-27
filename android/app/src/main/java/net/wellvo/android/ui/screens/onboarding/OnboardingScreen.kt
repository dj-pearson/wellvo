package net.wellvo.android.ui.screens.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import net.wellvo.android.viewmodels.OnboardingStep
import net.wellvo.android.viewmodels.OnboardingViewModel
import net.wellvo.android.viewmodels.UserTypeSelection

@Composable
fun OnboardingScreen(
    onComplete: () -> Unit = {},
    viewModel: OnboardingViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsState()

    if (state.isComplete) {
        onComplete()
        return
    }

    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // Progress indicator + back button
        OnboardingHeader(
            stepIndex = viewModel.stepIndex,
            totalSteps = viewModel.totalSteps,
            canGoBack = state.currentStep != OnboardingStep.Welcome && state.currentStep != OnboardingStep.Complete,
            onBack = viewModel::goBack
        )

        // Step content
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            when (state.currentStep) {
                OnboardingStep.Welcome -> WelcomeStep(onGetStarted = viewModel::advance)
                OnboardingStep.UserType -> UserTypeStep(
                    selected = state.selectedUserType,
                    onSelect = viewModel::selectUserType
                )
                OnboardingStep.CreateFamily -> CreateFamilyStep(
                    familyName = state.familyName,
                    onNameChange = viewModel::updateFamilyName,
                    isLoading = state.isLoading,
                    errorMessage = state.errorMessage,
                    onCreate = viewModel::createFamily
                )
                OnboardingStep.ChoosePlan -> ChoosePlanStep(
                    selectedPlan = state.selectedPlan,
                    onSelectPlan = viewModel::selectPlan,
                    onContinue = viewModel::advance
                )
                OnboardingStep.AddReceiver -> AddReceiverStep(
                    receiverName = state.receiverName,
                    receiverPhone = state.receiverPhone,
                    checkinHour = state.checkinHour,
                    checkinMinute = state.checkinMinute,
                    onNameChange = viewModel::updateReceiverName,
                    onPhoneChange = viewModel::updateReceiverPhone,
                    onTimeChange = viewModel::updateCheckinTime,
                    isLoading = state.isLoading,
                    errorMessage = state.errorMessage,
                    onInvite = viewModel::inviteReceiver,
                    onSkip = viewModel::skipAddReceiver
                )
                OnboardingStep.Notifications -> NotificationsStep(
                    onPermissionResult = viewModel::onNotificationPermissionResult,
                    checkPermission = viewModel::checkNotificationPermission
                )
                OnboardingStep.Complete -> CompleteStep(onGoToDashboard = onComplete)
            }
        }
    }
}

@Composable
private fun OnboardingHeader(
    stepIndex: Int,
    totalSteps: Int,
    canGoBack: Boolean,
    onBack: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (canGoBack) {
                IconButton(onClick = onBack) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back"
                    )
                }
            } else {
                Spacer(modifier = Modifier.size(48.dp))
            }
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = "Step ${stepIndex + 1} of $totalSteps",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.width(16.dp))
        }
        LinearProgressIndicator(
            progress = { (stepIndex + 1).toFloat() / totalSteps },
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.primary
        )
    }
}

@Composable
private fun WelcomeStep(onGetStarted: () -> Unit) {
    Spacer(modifier = Modifier.height(48.dp))

    Icon(
        imageVector = Icons.Default.Favorite,
        contentDescription = null,
        modifier = Modifier.size(80.dp),
        tint = MaterialTheme.colorScheme.primary
    )

    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = "Welcome to Wellvo",
        style = MaterialTheme.typography.headlineLarge,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "Wellvo helps families stay connected with a simple daily check-in. Set up your family, invite your loved ones, and get peace of mind with just one tap.",
        style = MaterialTheme.typography.bodyLarge,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    Spacer(modifier = Modifier.height(48.dp))

    Button(
        onClick = onGetStarted,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text("Get Started")
    }
}

@Composable
private fun UserTypeStep(
    selected: UserTypeSelection?,
    onSelect: (UserTypeSelection) -> Unit
) {
    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = "Who are you checking in on?",
        style = MaterialTheme.typography.headlineMedium,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(8.dp))

    Text(
        text = "This helps us tailor your experience",
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(32.dp))

    UserTypeSelection.entries.forEach { type ->
        val icon = when (type) {
            UserTypeSelection.AgingParent -> Icons.Default.People
            UserTypeSelection.Teenager -> Icons.Default.Person
            UserTypeSelection.Other -> Icons.Default.People
        }

        OutlinedCard(
            onClick = { onSelect(type) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 6.dp),
            border = BorderStroke(
                width = if (selected == type) 2.dp else 1.dp,
                color = if (selected == type) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.outline
            )
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(16.dp))
                Column {
                    Text(
                        text = type.label,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = type.description,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun CreateFamilyStep(
    familyName: String,
    onNameChange: (String) -> Unit,
    isLoading: Boolean,
    errorMessage: String?,
    onCreate: () -> Unit
) {
    val keyboardController = LocalSoftwareKeyboardController.current

    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = "Name your family group",
        style = MaterialTheme.typography.headlineMedium,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(8.dp))

    Text(
        text = "This is how your family will appear in the app",
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(32.dp))

    OutlinedTextField(
        value = familyName,
        onValueChange = onNameChange,
        label = { Text("Family Name") },
        placeholder = { Text("e.g., The Smiths") },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = {
            keyboardController?.hide()
            onCreate()
        }),
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        enabled = !isLoading
    )

    errorMessage?.let {
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = it,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall
        )
    }

    Spacer(modifier = Modifier.height(24.dp))

    if (isLoading) {
        CircularProgressIndicator()
    } else {
        Button(
            onClick = onCreate,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Create Family")
        }
    }
}

@Composable
private fun ChoosePlanStep(
    selectedPlan: String,
    onSelectPlan: (String) -> Unit,
    onContinue: () -> Unit
) {
    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = "Choose your plan",
        style = MaterialTheme.typography.headlineMedium,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(8.dp))

    Text(
        text = "You can change this anytime",
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(24.dp))

    data class PlanInfo(val id: String, val name: String, val price: String, val features: List<String>)

    val plans = listOf(
        PlanInfo("free", "Free", "Free", listOf("1 receiver", "Daily check-ins", "Basic alerts")),
        PlanInfo("family", "Family", "$4.99/mo", listOf("Up to 5 receivers", "Mood tracking", "Check-in history", "Priority alerts")),
        PlanInfo("family_plus", "Family+", "$9.99/mo", listOf("Up to 10 receivers", "Location tracking", "PDF reports", "Kid mode", "All Family features"))
    )

    plans.forEach { plan ->
        val isSelected = selectedPlan == plan.id
        OutlinedCard(
            onClick = { onSelectPlan(plan.id) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 6.dp),
            border = BorderStroke(
                width = if (isSelected) 2.dp else 1.dp,
                color = if (isSelected) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.outline
            )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = plan.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = plan.price,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                plan.features.forEach { feature ->
                    Text(
                        text = "• $feature",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }

    Spacer(modifier = Modifier.height(24.dp))

    Button(
        onClick = onContinue,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text("Continue")
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddReceiverStep(
    receiverName: String,
    receiverPhone: String,
    checkinHour: Int,
    checkinMinute: Int,
    onNameChange: (String) -> Unit,
    onPhoneChange: (String) -> Unit,
    onTimeChange: (Int, Int) -> Unit,
    isLoading: Boolean,
    errorMessage: String?,
    onInvite: () -> Unit,
    onSkip: () -> Unit
) {
    val keyboardController = LocalSoftwareKeyboardController.current
    val timePickerState = rememberTimePickerState(
        initialHour = checkinHour,
        initialMinute = checkinMinute,
        is24Hour = false
    )

    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = "Invite your first receiver",
        style = MaterialTheme.typography.headlineMedium,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(8.dp))

    Text(
        text = "They'll get a text with instructions to join",
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(24.dp))

    OutlinedTextField(
        value = receiverName,
        onValueChange = onNameChange,
        label = { Text("Receiver's Name") },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        enabled = !isLoading
    )

    Spacer(modifier = Modifier.height(12.dp))

    OutlinedTextField(
        value = receiverPhone,
        onValueChange = onPhoneChange,
        label = { Text("+1 Phone Number") },
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Phone,
            imeAction = ImeAction.Done
        ),
        keyboardActions = KeyboardActions(onDone = { keyboardController?.hide() }),
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        enabled = !isLoading
    )

    Spacer(modifier = Modifier.height(20.dp))

    Text(
        text = "Daily check-in time",
        style = MaterialTheme.typography.titleMedium
    )

    Spacer(modifier = Modifier.height(8.dp))

    TimePicker(
        state = timePickerState,
        modifier = Modifier.fillMaxWidth()
    )

    // Sync time picker state back to view model
    val currentHour = timePickerState.hour
    val currentMinute = timePickerState.minute
    if (currentHour != checkinHour || currentMinute != checkinMinute) {
        onTimeChange(currentHour, currentMinute)
    }

    errorMessage?.let {
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = it,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall
        )
    }

    Spacer(modifier = Modifier.height(24.dp))

    if (isLoading) {
        CircularProgressIndicator()
    } else {
        Button(
            onClick = onInvite,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Send Invite")
        }

        Spacer(modifier = Modifier.height(8.dp))

        TextButton(
            onClick = onSkip,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Skip for now")
        }
    }
}

@Composable
private fun NotificationsStep(
    onPermissionResult: (Boolean) -> Unit,
    checkPermission: (android.content.Context) -> Boolean
) {
    val context = LocalContext.current

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        onPermissionResult(granted)
    }

    Spacer(modifier = Modifier.height(48.dp))

    Icon(
        imageVector = Icons.Default.Notifications,
        contentDescription = null,
        modifier = Modifier.size(80.dp),
        tint = MaterialTheme.colorScheme.primary
    )

    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = "Stay in the loop",
        style = MaterialTheme.typography.headlineMedium,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "Enable notifications so you'll know right away when your receiver checks in — or if they miss a check-in and need a follow-up.",
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
private fun CompleteStep(onGoToDashboard: () -> Unit) {
    Spacer(modifier = Modifier.height(48.dp))

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
        text = "Your family group is ready. You can invite more receivers and manage settings from your dashboard.",
        style = MaterialTheme.typography.bodyLarge,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    Spacer(modifier = Modifier.height(48.dp))

    Button(
        onClick = onGoToDashboard,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text("Go to Dashboard")
    }
}
