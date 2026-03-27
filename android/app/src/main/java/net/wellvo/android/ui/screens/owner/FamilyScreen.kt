package net.wellvo.android.ui.screens.owner

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import net.wellvo.android.data.models.FamilyMember
import net.wellvo.android.data.models.MemberStatus
import net.wellvo.android.data.models.SubscriptionTier
import net.wellvo.android.data.models.UserRole
import net.wellvo.android.viewmodels.FamilyViewModel

private val TierGreen = Color(0xFF22C55E)
private val TierBlue = Color(0xFF3B82F6)
private val TierPurple = Color(0xFF8B5CF6)
private val StatusActive = Color(0xFF22C55E)
private val StatusInvited = Color(0xFFF59E0B)
private val StatusDeactivated = Color(0xFF9CA3AF)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FamilyScreen(
    viewModel: FamilyViewModel,
    userId: String,
    modifier: Modifier = Modifier
) {
    val family by viewModel.family.collectAsState()
    val members by viewModel.members.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val successMessage by viewModel.successMessage.collectAsState()
    val haptic = LocalHapticFeedback.current
    val snackbarHostState = remember { SnackbarHostState() }
    var showInviteSheet by remember { mutableStateOf(false) }
    var memberToRemove by remember { mutableStateOf<FamilyMember?>(null) }
    var memberToTransfer by remember { mutableStateOf<FamilyMember?>(null) }

    LaunchedEffect(userId) {
        viewModel.loadFamily(userId)
    }

    LaunchedEffect(errorMessage) {
        errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    LaunchedEffect(successMessage) {
        successMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearSuccessMessage()
        }
    }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    showInviteSheet = true
                },
                containerColor = MaterialTheme.colorScheme.primary
            ) {
                Icon(Icons.Default.PersonAdd, contentDescription = "Invite Receiver")
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { innerPadding ->
        PullToRefreshBox(
            isRefreshing = isLoading,
            onRefresh = { viewModel.loadFamily(userId) },
            modifier = modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            when {
                isLoading && members.isEmpty() && family == null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }

                family == null && !isLoading -> {
                    EmptyFamilyState()
                }

                else -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        // Family header
                        family?.let { fam ->
                            item {
                                FamilyHeaderCard(
                                    familyName = fam.name,
                                    tier = fam.subscriptionTier
                                )
                            }
                        }

                        if (members.isEmpty()) {
                            item {
                                EmptyMembersState()
                            }
                        } else {
                            items(members, key = { it.id }) { member ->
                                MemberCard(
                                    member = member,
                                    onRemove = { memberToRemove = member },
                                    onResendInvite = { viewModel.resendInvite(member) },
                                    onTransferOwnership = { memberToTransfer = member }
                                )
                            }
                        }

                        item { Spacer(modifier = Modifier.height(72.dp)) }
                    }
                }
            }
        }
    }

    // Remove member confirmation dialog
    memberToRemove?.let { member ->
        AlertDialog(
            onDismissRequest = { memberToRemove = null },
            title = { Text("Remove Member") },
            text = {
                Text("Are you sure you want to remove ${member.user?.displayName ?: "this member"} from the family?")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        viewModel.removeMember(member.id, member.user?.displayName ?: "Member")
                        memberToRemove = null
                    }
                ) {
                    Text("Remove", color = Color(0xFFEF4444))
                }
            },
            dismissButton = {
                TextButton(onClick = { memberToRemove = null }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Transfer ownership confirmation dialog
    memberToTransfer?.let { member ->
        AlertDialog(
            onDismissRequest = { memberToTransfer = null },
            title = { Text("Transfer Ownership") },
            text = {
                Text("Are you sure you want to transfer ownership to ${member.user?.displayName ?: "this member"}? You will become a Viewer and lose control of settings and billing.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.transferOwnership(member.id, member.user?.displayName ?: "Member")
                        memberToTransfer = null
                    }
                ) {
                    Text("Transfer", color = Color(0xFFEF4444))
                }
            },
            dismissButton = {
                TextButton(onClick = { memberToTransfer = null }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Invite Receiver bottom sheet
    if (showInviteSheet) {
        InviteReceiverSheet(
            viewModel = viewModel,
            onDismiss = {
                showInviteSheet = false
                viewModel.resetInviteState()
            }
        )
    }
}

@Composable
private fun FamilyHeaderCard(familyName: String, tier: SubscriptionTier) {
    val tierColor = when (tier) {
        SubscriptionTier.Free -> TierGreen
        SubscriptionTier.Family -> TierBlue
        SubscriptionTier.FamilyPlus -> TierPurple
    }
    val tierLabel = when (tier) {
        SubscriptionTier.Free -> "Free"
        SubscriptionTier.Family -> "Family"
        SubscriptionTier.FamilyPlus -> "Family+"
    }

    Card(
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.People,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = familyName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.weight(1f)
            )
            Text(
                text = tierLabel,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                modifier = Modifier
                    .background(tierColor, MaterialTheme.shapes.small)
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun MemberCard(
    member: FamilyMember,
    onRemove: () -> Unit,
    onResendInvite: () -> Unit,
    onTransferOwnership: () -> Unit
) {
    var showContextMenu by remember { mutableStateOf(false) }
    val isOwner = member.role == UserRole.Owner

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart && !isOwner) {
                onRemove()
            }
            false // Don't actually dismiss, let the dialog handle it
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        enableDismissFromEndToStart = !isOwner,
        backgroundContent = {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0xFFEF4444), MaterialTheme.shapes.medium)
                    .padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd
            ) {
                Icon(
                    imageVector = Icons.Default.Delete,
                    contentDescription = "Remove member",
                    tint = Color.White
                )
            }
        }
    ) {
        Card(
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            ),
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClick = {},
                    onLongClick = {
                        if (!isOwner) showContextMenu = true
                    }
                )
                .semantics {
                    contentDescription = "${member.user?.displayName ?: "Unknown"}, ${member.role.name}, ${member.status.name}"
                }
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = member.user?.displayName ?: "Unknown",
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // Role badge
                        val roleColor = when (member.role) {
                            UserRole.Owner -> TierPurple
                            UserRole.Receiver -> TierBlue
                            UserRole.Viewer -> StatusDeactivated
                        }
                        Text(
                            text = member.role.name,
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White,
                            modifier = Modifier
                                .background(roleColor, MaterialTheme.shapes.small)
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        )

                        // Status badge
                        val statusColor = when (member.status) {
                            MemberStatus.Active -> StatusActive
                            MemberStatus.Invited -> StatusInvited
                            MemberStatus.Deactivated -> StatusDeactivated
                        }
                        Text(
                            text = member.status.name,
                            style = MaterialTheme.typography.labelSmall,
                            color = statusColor
                        )
                    }
                }

                // Context menu actions for non-owner members
                if (!isOwner) {
                    Box {
                        DropdownMenu(
                            expanded = showContextMenu,
                            onDismissRequest = { showContextMenu = false }
                        ) {
                            if (member.status == MemberStatus.Active) {
                                DropdownMenuItem(
                                    text = { Text("Transfer Ownership") },
                                    leadingIcon = {
                                        Icon(Icons.Default.SwapHoriz, contentDescription = null)
                                    },
                                    onClick = {
                                        showContextMenu = false
                                        onTransferOwnership()
                                    }
                                )
                            }
                            if (member.status == MemberStatus.Invited) {
                                DropdownMenuItem(
                                    text = { Text("Re-send Invite") },
                                    leadingIcon = {
                                        Icon(Icons.Default.Refresh, contentDescription = null)
                                    },
                                    onClick = {
                                        showContextMenu = false
                                        onResendInvite()
                                    }
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("Remove", color = Color(0xFFEF4444)) },
                                leadingIcon = {
                                    Icon(Icons.Default.Delete, contentDescription = null, tint = Color(0xFFEF4444))
                                },
                                onClick = {
                                    showContextMenu = false
                                    onRemove()
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private val phoneRegex = Regex(
    "^(\\+1\\d{10}|\\d{10}|\\d{3}-\\d{3}-\\d{4}|\\(\\d{3}\\)\\s?\\d{3}-\\d{4})$"
)

private fun isValidPhone(phone: String): Boolean {
    return phoneRegex.matches(phone.trim())
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InviteReceiverSheet(
    viewModel: FamilyViewModel,
    onDismiss: () -> Unit
) {
    var name by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var phoneInteracted by remember { mutableStateOf(false) }
    var showSetupGuide by remember { mutableStateOf(false) }
    val timePickerState = rememberTimePickerState(initialHour = 8, initialMinute = 0)

    val isInviting by viewModel.isInviting.collectAsState()
    val inviteSuccess by viewModel.inviteSuccess.collectAsState()
    val inviteError by viewModel.inviteError.collectAsState()

    val phoneValid = isValidPhone(phone)
    val canSend = name.isNotBlank() && phoneValid && !isInviting

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (!inviteSuccess) {
                Text(
                    text = "Invite Receiver",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )

                // How it works section
                Card(
                    shape = MaterialTheme.shapes.medium,
                    colors = CardDefaults.cardColors(
                        containerColor = Color(0xFFF0FDF4)
                    )
                ) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Text(
                            text = "How It Works",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = Color(0xFF22C55E)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        InstructionStep(1, "Enter their name and phone number below")
                        InstructionStep(2, "They'll receive a text with a download link")
                        InstructionStep(3, "They download the app and sign in with that phone number")
                        InstructionStep(4, "The app automatically connects them — no codes needed")
                    }
                }

                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                OutlinedTextField(
                    value = phone,
                    onValueChange = {
                        phone = it
                        phoneInteracted = true
                    },
                    label = { Text("Phone Number") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    isError = phoneInteracted && phone.isNotEmpty() && !phoneValid,
                    supportingText = {
                        if (phoneInteracted && phone.isNotEmpty() && !phoneValid) {
                            Text(
                                "Enter a valid US phone number",
                                color = MaterialTheme.colorScheme.error
                            )
                        } else {
                            Text("Use the number they'll sign into the app with")
                        }
                    }
                )

                // Material 3 TimePicker for daily check-in time
                Text(
                    text = "Daily Check-in Time",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )

                Box(
                    modifier = Modifier.fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    TimePicker(state = timePickerState)
                }

                // Error message from ViewModel
                inviteError?.let { error ->
                    Card(
                        shape = MaterialTheme.shapes.small,
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.errorContainer
                        )
                    ) {
                        Text(
                            text = error,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(12.dp)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(4.dp))

                androidx.compose.material3.Button(
                    onClick = {
                        if (canSend) {
                            val timeStr = "%02d:%02d".format(timePickerState.hour, timePickerState.minute)
                            viewModel.inviteReceiver(name.trim(), phone.trim(), timeStr, "standard")
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = canSend,
                    shape = MaterialTheme.shapes.large
                ) {
                    if (isInviting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            color = Color.White,
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Sending...")
                    } else {
                        Icon(Icons.Default.PersonAdd, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Send Invitation")
                    }
                }
            } else if (showSetupGuide) {
                // Full setup guide
                ReceiverSetupGuideScreen(
                    receiverName = name,
                    onDone = { showSetupGuide = false }
                )
            } else {
                // Success state
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(
                        imageVector = Icons.Default.CheckCircle,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = Color(0xFF22C55E)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = "Invitation Sent!",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "A text message has been sent to $phone with instructions to download and set up the app.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Setup instructions
                Card(
                    shape = MaterialTheme.shapes.medium,
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    )
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "How $name Sets Up",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        InstructionStep(1, "They'll receive an SMS with a download link")
                        InstructionStep(2, "Download the app from the App Store or Play Store")
                        InstructionStep(3, "Sign in with the phone number you invited them with")
                        InstructionStep(4, "The app will automatically connect them to your family")
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // View Setup Guide button
                Card(
                    shape = MaterialTheme.shapes.medium,
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    ),
                    onClick = { showSetupGuide = true }
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "View Full Setup Guide for $name",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f)
                        )
                        Icon(
                            imageVector = Icons.Default.ArrowForward,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Done")
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun InstructionStep(number: Int, text: String) {
    Row(
        modifier = Modifier.padding(vertical = 4.dp),
        verticalAlignment = Alignment.Top
    ) {
        Text(
            text = "$number.",
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(20.dp)
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun EmptyFamilyState() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.People,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(20.dp))
        Text(
            text = "No Family Yet",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Create a family to start adding receivers.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun EmptyMembersState() {
    Card(
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Default.PersonAdd,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "No receivers yet.",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Invite someone to get started.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
