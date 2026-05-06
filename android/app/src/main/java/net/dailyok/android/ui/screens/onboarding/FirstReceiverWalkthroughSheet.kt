package net.dailyok.android.ui.screens.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import net.dailyok.android.ui.theme.DailyOKGreen100
import net.dailyok.android.ui.theme.DailyOKGreen500
import net.dailyok.android.ui.theme.DailyOKGreen700
import net.dailyok.android.ui.theme.DailyOKSpacing
import net.dailyok.android.viewmodels.FamilyViewModel

/**
 * Multi-step walkthrough that runs an owner from "no receivers yet" to a sent
 * invite. Auto-launches on the Dashboard the first time it loads empty, and
 * can be re-opened from the Dashboard empty state's CTA.
 *
 * Steps: Welcome → How it works → Receiver details (form) → Invite sent
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FirstReceiverWalkthroughSheet(
    viewModel: FamilyViewModel,
    onDismiss: () -> Unit,
    onInviteSent: () -> Unit,
) {
    var step by remember { mutableIntStateOf(0) }
    var name by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var phoneInteracted by remember { mutableStateOf(false) }
    val timePickerState = rememberTimePickerState(initialHour = 8, initialMinute = 0)

    val isInviting by viewModel.isInviting.collectAsState()
    val inviteSuccess by viewModel.inviteSuccess.collectAsState()
    val inviteError by viewModel.inviteError.collectAsState()

    LaunchedEffect(inviteSuccess) {
        if (inviteSuccess) {
            step = 3
            onInviteSent()
        }
    }

    // Reset the shared FamilyViewModel invite flags on close so re-entering
    // the walkthrough starts clean (and doesn't bounce straight to success).
    DisposableEffect(Unit) {
        onDispose { viewModel.resetInviteState() }
    }

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val phoneValid = isLikelyPhone(phone)
    val canSubmit = name.isNotBlank() && phoneValid && !isInviting

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 580.dp)
        ) {
            StepIndicator(currentStep = step, totalSteps = 4)

            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                AnimatedContent(
                    targetState = step,
                    transitionSpec = {
                        if (targetState >= initialState) {
                            (slideInRight() + fadeIn(tween(220))) togetherWith
                                (slideOutLeft() + fadeOut(tween(180)))
                        } else {
                            (slideInLeft() + fadeIn(tween(220))) togetherWith
                                (slideOutRight() + fadeOut(tween(180)))
                        }
                    },
                    label = "walkthrough_step",
                    modifier = Modifier.fillMaxSize()
                ) { current ->
                    when (current) {
                        0 -> WelcomeStep()
                        1 -> HowItWorksStep()
                        2 -> ReceiverDetailsStep(
                            name = name,
                            onNameChange = { name = it },
                            phone = phone,
                            onPhoneChange = {
                                phone = it
                                phoneInteracted = true
                            },
                            phoneValid = phoneValid,
                            phoneInteracted = phoneInteracted,
                            timePickerState = timePickerState,
                            errorMessage = inviteError
                        )
                        3 -> InviteSentStep(
                            name = name.ifBlank { "they" },
                            phone = phone
                        )
                    }
                }
            }

            Footer(
                step = step,
                isLoading = isInviting,
                primaryEnabled = when (step) {
                    2 -> canSubmit
                    else -> true
                },
                onBack = {
                    if (step > 0) step--
                },
                onPrimary = {
                    when (step) {
                        0, 1 -> step++
                        2 -> if (canSubmit) {
                            val timeStr = "%02d:%02d".format(
                                timePickerState.hour,
                                timePickerState.minute
                            )
                            viewModel.inviteReceiver(
                                name.trim(),
                                phone.trim(),
                                timeStr,
                                "standard"
                            )
                        }
                        3 -> onDismiss()
                    }
                },
                onSkip = onDismiss
            )
        }
    }
}

// MARK: - Step indicator

@Composable
private fun StepIndicator(currentStep: Int, totalSteps: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = DailyOKSpacing.xs, bottom = DailyOKSpacing.sm),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        repeat(totalSteps) { index ->
            val isActive = index == currentStep
            val isPast = index < currentStep
            val targetWidth = if (isActive) 28.dp else 10.dp
            val width by animateDpAsState(
                targetValue = targetWidth,
                animationSpec = tween(durationMillis = 220),
                label = "stepWidth"
            )
            Box(
                modifier = Modifier
                    .padding(horizontal = 4.dp)
                    .width(width)
                    .height(8.dp)
                    .clip(RoundedCornerShape(50))
                    .background(
                        if (isActive || isPast) DailyOKGreen500
                        else MaterialTheme.colorScheme.outlineVariant
                    )
            )
        }
    }
}

// MARK: - Steps

@Composable
private fun WelcomeStep() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = DailyOKSpacing.xl, vertical = DailyOKSpacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DailyOKSpacing.lg)
    ) {
        Box(
            modifier = Modifier
                .size(160.dp)
                .clip(CircleShape)
                .background(DailyOKGreen100),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.People,
                contentDescription = null,
                modifier = Modifier.size(72.dp),
                tint = DailyOKGreen700
            )
        }

        Text(
            text = "Let's add your first family member",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )

        Text(
            text = "Daily OK helps you stay connected with the people who matter — a one-tap check-in, peace of mind every day.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun HowItWorksStep() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = DailyOKSpacing.xl, vertical = DailyOKSpacing.lg),
        verticalArrangement = Arrangement.spacedBy(DailyOKSpacing.lg)
    ) {
        Text(
            text = "Here's how it works",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        FlowStepRow(
            number = 1,
            icon = Icons.Default.Notifications,
            title = "We send them a daily reminder",
            body = "At the time you choose, your family member gets a notification asking how they're doing."
        )
        FlowStepRow(
            number = 2,
            icon = Icons.Default.CheckCircle,
            title = "They tap \"I'm OK\"",
            body = "One tap. No typing. They can also share a quick mood or note if they want."
        )
        FlowStepRow(
            number = 3,
            icon = Icons.Default.Favorite,
            title = "You see they checked in",
            body = "Their status updates here on your dashboard. If they miss a check-in, you'll get an alert."
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReceiverDetailsStep(
    name: String,
    onNameChange: (String) -> Unit,
    phone: String,
    onPhoneChange: (String) -> Unit,
    phoneValid: Boolean,
    phoneInteracted: Boolean,
    timePickerState: androidx.compose.material3.TimePickerState,
    errorMessage: String?,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = DailyOKSpacing.xl, vertical = DailyOKSpacing.md),
        verticalArrangement = Arrangement.spacedBy(DailyOKSpacing.md)
    ) {
        Text(
            text = "Who are you adding?",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )

        OutlinedTextField(
            value = name,
            onValueChange = onNameChange,
            label = { Text("Their name") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        OutlinedTextField(
            value = phone,
            onValueChange = onPhoneChange,
            label = { Text("Phone number") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            isError = phoneInteracted && phone.isNotEmpty() && !phoneValid,
            supportingText = {
                if (phoneInteracted && phone.isNotEmpty() && !phoneValid) {
                    Text(
                        "Enter a valid phone number",
                        color = MaterialTheme.colorScheme.error
                    )
                } else {
                    Text("Use the number they'll sign into the app with — that's how we connect them automatically.")
                }
            }
        )

        Text(
            text = "When should we ask them?",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = DailyOKSpacing.xs)
        )

        Box(
            modifier = Modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center
        ) {
            TimePicker(state = timePickerState)
        }

        Text(
            text = "You can fine-tune the schedule anytime later — weekday/weekend, per-day, pause, escalation alerts, and more.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (errorMessage != null) {
            Card(
                shape = MaterialTheme.shapes.small,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                )
            ) {
                Text(
                    text = errorMessage,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(12.dp)
                )
            }
        }
    }
}

@Composable
private fun InviteSentStep(name: String, phone: String) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = DailyOKSpacing.xl, vertical = DailyOKSpacing.lg),
        verticalArrangement = Arrangement.spacedBy(DailyOKSpacing.md)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = DailyOKGreen500
            )
            Spacer(modifier = Modifier.height(DailyOKSpacing.sm))
            Text(
                text = "Invite sent to $name!",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "They'll get a text at $phone with a link to download Daily OK.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }

        Spacer(modifier = Modifier.height(DailyOKSpacing.xs))

        Text(
            text = "What $name does next:",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )

        ReceiverFlowRow(1, Icons.Default.Sms, "Opens the text message you triggered.")
        ReceiverFlowRow(2, Icons.Default.ArrowDownward, "Taps the link to download Daily OK.")
        ReceiverFlowRow(3, Icons.Default.Phone, "Signs in with the same phone number — no codes to type.")
        ReceiverFlowRow(4, Icons.Default.Notifications, "Allows notifications so they get the daily reminder.")
        ReceiverFlowRow(5, Icons.Default.ThumbUp, "Done. Each day they'll just tap \"I'm OK.\"")

        Card(
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF7ED))
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Lightbulb,
                        contentDescription = null,
                        tint = Color(0xFFF97316),
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Tip",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(0xFFF97316)
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "If they don't see the text, double-check the phone number and re-send the invite from the Family tab.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

// MARK: - Footer

@Composable
private fun Footer(
    step: Int,
    isLoading: Boolean,
    primaryEnabled: Boolean,
    onBack: () -> Unit,
    onPrimary: () -> Unit,
    onSkip: () -> Unit,
) {
    val showBack = step in 1..2
    val showSkip = step < 3

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = DailyOKSpacing.lg, vertical = DailyOKSpacing.md)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(DailyOKSpacing.sm)
        ) {
            if (showBack) {
                OutlinedButton(
                    onClick = onBack,
                    modifier = Modifier.weight(1f),
                    shape = MaterialTheme.shapes.large
                ) {
                    Text("Back")
                }
            }
            Button(
                onClick = onPrimary,
                modifier = Modifier.weight(if (showBack) 1.5f else 1f),
                enabled = primaryEnabled,
                shape = MaterialTheme.shapes.large
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Sending…")
                } else {
                    val label = when (step) {
                        0, 1 -> "Next"
                        2 -> "Send Invite"
                        3 -> "Done"
                        else -> "Next"
                    }
                    if (step == 2 && !isLoading) {
                        Icon(
                            imageVector = Icons.Default.Send,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text(label)
                }
            }
        }

        if (showSkip) {
            Spacer(modifier = Modifier.height(4.dp))
            TextButton(
                onClick = onSkip,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            ) {
                Text(
                    text = "Skip for now",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

// MARK: - Helpers

@Composable
private fun FlowStepRow(
    number: Int,
    icon: ImageVector,
    title: String,
    body: String,
) {
    Row(
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(DailyOKSpacing.sm)
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(DailyOKGreen100),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = DailyOKGreen700,
                modifier = Modifier.size(22.dp)
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "$number.",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = DailyOKGreen700
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
            }
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = body,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ReceiverFlowRow(number: Int, icon: ImageVector, text: String) {
    Row(
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(DailyOKSpacing.sm)
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(DailyOKGreen500),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "$number",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
        }
        Row(
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = DailyOKGreen500,
                modifier = Modifier
                    .size(16.dp)
                    .padding(top = 3.dp)
            )
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

private fun isLikelyPhone(phone: String): Boolean {
    val digits = phone.filter { it.isDigit() }
    return digits.length in 10..15
}

// Slide animation factories — kept terse on purpose so the AnimatedContent
// transitionSpec block stays readable.
private fun AnimatedContentTransitionScope<Int>.slideInRight() =
    androidx.compose.animation.slideInHorizontally(tween(220)) { it / 2 }

private fun AnimatedContentTransitionScope<Int>.slideOutLeft() =
    androidx.compose.animation.slideOutHorizontally(tween(220)) { -it / 2 }

private fun AnimatedContentTransitionScope<Int>.slideInLeft() =
    androidx.compose.animation.slideInHorizontally(tween(220)) { -it / 2 }

private fun AnimatedContentTransitionScope<Int>.slideOutRight() =
    androidx.compose.animation.slideOutHorizontally(tween(220)) { it / 2 }
