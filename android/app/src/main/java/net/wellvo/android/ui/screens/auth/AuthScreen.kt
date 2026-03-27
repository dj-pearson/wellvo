package net.wellvo.android.ui.screens.auth

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import net.wellvo.android.R
import net.wellvo.android.viewmodels.AuthUiState
import net.wellvo.android.viewmodels.AuthViewModel

@Composable
fun AuthScreen(
    viewModel: AuthViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    var selectedTab by remember { mutableIntStateOf(0) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(64.dp))
        Text(
            text = "Wellvo",
            style = MaterialTheme.typography.displayLarge,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "One tap. Peace of mind.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(32.dp))

        GoogleSignInButton(
            isLoading = state.isGoogleLoading,
            enabled = !state.isLoading && !state.isGoogleLoading,
            onClick = { viewModel.signInWithGoogle(context) }
        )

        if (state.isGoogleLoading && state.errorMessage != null) {
            ErrorText(state.errorMessage)
        }

        Spacer(modifier = Modifier.height(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            HorizontalDivider(modifier = Modifier.weight(1f))
            Text(
                text = "or",
                modifier = Modifier.padding(horizontal = 16.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            HorizontalDivider(modifier = Modifier.weight(1f))
        }

        Spacer(modifier = Modifier.height(16.dp))

        TabRow(selectedTabIndex = selectedTab) {
            Tab(selected = selectedTab == 0, onClick = { selectedTab = 0 }) {
                Text("Phone", modifier = Modifier.padding(16.dp))
            }
            Tab(selected = selectedTab == 1, onClick = { selectedTab = 1 }) {
                Text("Email", modifier = Modifier.padding(16.dp))
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        when (selectedTab) {
            0 -> PhoneAuthSection(state = state, viewModel = viewModel)
            1 -> EmailAuthSection(state = state, viewModel = viewModel)
        }
    }
}

@Composable
private fun GoogleSignInButton(
    isLoading: Boolean,
    enabled: Boolean,
    onClick: () -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().height(48.dp),
        enabled = enabled,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text("Signing in...")
        } else {
            Icon(
                painter = painterResource(id = R.drawable.ic_google),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = androidx.compose.ui.graphics.Color.Unspecified
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text("Continue with Google")
        }
    }
}

@Composable
private fun PhoneAuthSection(
    state: AuthUiState,
    viewModel: AuthViewModel
) {
    val otpFocusRequester = remember { FocusRequester() }

    if (!state.isAwaitingOTP) {
        Text(
            text = "Enter your phone number",
            style = MaterialTheme.typography.titleLarge
        )
        Spacer(modifier = Modifier.height(16.dp))

        OutlinedTextField(
            value = state.phoneNumber,
            onValueChange = viewModel::updatePhoneNumber,
            label = { Text("+1 Phone Number") },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Phone,
                imeAction = ImeAction.Done
            ),
            keyboardActions = KeyboardActions(onDone = { viewModel.sendOTP() }),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            enabled = !state.isLoading
        )

        ErrorText(state.errorMessage)
        Spacer(modifier = Modifier.height(24.dp))
        LoadingOrButton(isLoading = state.isLoading, label = "Send Code", onClick = viewModel::sendOTP)
    } else {
        Text(
            text = "Enter verification code",
            style = MaterialTheme.typography.titleLarge
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "We sent a 6-digit code to your phone",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))

        OutlinedTextField(
            value = state.otpCode,
            onValueChange = { if (it.length <= 6) viewModel.updateOtpCode(it) },
            label = { Text("6-digit code") },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Number,
                imeAction = ImeAction.Done
            ),
            keyboardActions = KeyboardActions(onDone = { viewModel.verifyOTP() }),
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(otpFocusRequester),
            enabled = !state.isLoading
        )

        ErrorText(state.errorMessage)
        Spacer(modifier = Modifier.height(24.dp))
        LoadingOrButton(isLoading = state.isLoading, label = "Verify", onClick = viewModel::verifyOTP)

        Spacer(modifier = Modifier.height(8.dp))
        TextButton(onClick = viewModel::backToPhoneEntry) {
            Text("Use a different number")
        }
    }
}

@Composable
private fun EmailAuthSection(
    state: AuthUiState,
    viewModel: AuthViewModel
) {
    if (state.isSignUp) {
        OutlinedTextField(
            value = state.displayName,
            onValueChange = viewModel::updateDisplayName,
            label = { Text("Display Name") },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            enabled = !state.isLoading
        )
        Spacer(modifier = Modifier.height(12.dp))
    }

    OutlinedTextField(
        value = state.email,
        onValueChange = viewModel::updateEmail,
        label = { Text("Email") },
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Email,
            imeAction = ImeAction.Next
        ),
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        enabled = !state.isLoading
    )
    Spacer(modifier = Modifier.height(12.dp))

    OutlinedTextField(
        value = state.password,
        onValueChange = viewModel::updatePassword,
        label = { Text("Password") },
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Password,
            imeAction = ImeAction.Done
        ),
        keyboardActions = KeyboardActions(onDone = { viewModel.signInWithEmail() }),
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        enabled = !state.isLoading
    )

    ErrorText(state.errorMessage)
    Spacer(modifier = Modifier.height(24.dp))
    LoadingOrButton(
        isLoading = state.isLoading,
        label = if (state.isSignUp) "Create Account" else "Sign In",
        onClick = viewModel::signInWithEmail
    )

    Spacer(modifier = Modifier.height(8.dp))
    TextButton(onClick = viewModel::toggleSignUp) {
        Text(
            if (state.isSignUp) "Already have an account? Sign In"
            else "Don't have an account? Sign Up"
        )
    }
}

@Composable
private fun ErrorText(message: String?) {
    message?.let {
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = it,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun LoadingOrButton(
    isLoading: Boolean,
    label: String,
    onClick: () -> Unit
) {
    if (isLoading) {
        CircularProgressIndicator()
    } else {
        Button(
            onClick = onClick,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(label)
        }
    }
}
