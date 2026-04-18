package net.dailyok.android.ui.screens.auth

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import net.dailyok.android.R
import net.dailyok.android.ui.components.AmbientBackground
import net.dailyok.android.ui.components.AmbientTone
import net.dailyok.android.ui.components.GlassCard
import net.dailyok.android.ui.theme.DailyOKElevation
import net.dailyok.android.ui.theme.DailyOKGlass
import net.dailyok.android.ui.theme.DailyOKGlassStyle
import net.dailyok.android.viewmodels.AuthUiState
import net.dailyok.android.viewmodels.AuthViewModel

// Password strength evaluation
private enum class PasswordStrength(val label: String, val progress: Float) {
    WEAK("Weak", 0.25f),
    FAIR("Fair", 0.5f),
    GOOD("Good", 0.75f),
    STRONG("Strong", 1.0f);

    companion object {
        private val commonPasswords = setOf(
            "password", "123456789", "1234567890", "qwerty1234", "iloveyou1",
            "password1", "password12", "password123",
        )

        fun evaluate(password: String): PasswordStrength {
            if (password.isEmpty()) return WEAK
            if (password.lowercase() in commonPasswords) return WEAK

            var score = 0
            if (password.length >= 10) score++
            if (password.length >= 14) score++
            if (password.any { it.isUpperCase() }) score++
            if (password.any { it.isLowerCase() }) score++
            if (password.any { it.isDigit() }) score++
            if (password.any { !it.isLetter() && !it.isDigit() }) score++

            return when (score) {
                in 0..2 -> WEAK
                3 -> FAIR
                in 4..5 -> GOOD
                else -> STRONG
            }
        }
    }
}

@Composable
fun AuthScreen(
    viewModel: AuthViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val keyboardController = LocalSoftwareKeyboardController.current

    Box(modifier = Modifier.fillMaxSize()) {
        AmbientBackground(tone = AmbientTone.Calm)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(72.dp))

            // Logo and tagline
            Text(
                text = stringResource(R.string.app_name),
                style = MaterialTheme.typography.displayLarge,
                color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.tagline),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(32.dp))

            GlassCard(
                modifier = Modifier.fillMaxWidth(),
                style = DailyOKGlassStyle.Regular,
                shape = RoundedCornerShape(DailyOKGlass.RadiusLarge),
                elevation = DailyOKElevation.level4,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    // Rate limiting lockout message
                    state.authLockoutMessage?.let { lockoutMsg ->
                        Text(
                            text = lockoutMsg,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)
                        )
                    }

                    // Phone OTP — primary, prominent
                    PhoneAuthSection(
                        state = state,
                        viewModel = viewModel,
                        onDismissKeyboard = { keyboardController?.hide() }
                    )

                    Spacer(modifier = Modifier.height(20.dp))

                    // Divider
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        HorizontalDivider(modifier = Modifier.weight(1f))
                        Text(
                            text = stringResource(R.string.auth_or_divider),
                            modifier = Modifier.padding(horizontal = 16.dp),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        HorizontalDivider(modifier = Modifier.weight(1f))
                    }

                    Spacer(modifier = Modifier.height(20.dp))

                    // Google Sign-In
                    GoogleSignInButton(
                        isLoading = state.isGoogleLoading,
                        enabled = !state.isLoading && !state.isGoogleLoading,
                        onClick = { viewModel.signInWithGoogle(context) }
                    )

                    if (state.isGoogleLoading && state.errorMessage != null) {
                        ErrorText(state.errorMessage)
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    // Email/Password — expandable section
                    EmailExpandableSection(
                        state = state,
                        viewModel = viewModel,
                        onDismissKeyboard = { keyboardController?.hide() }
                    )
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
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
            Text(stringResource(R.string.auth_signing_in))
        } else {
            Icon(
                painter = painterResource(id = R.drawable.ic_google),
                contentDescription = stringResource(R.string.cd_google_icon),
                modifier = Modifier.size(20.dp),
                tint = androidx.compose.ui.graphics.Color.Unspecified
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(stringResource(R.string.auth_continue_google))
        }
    }
}

@Composable
private fun PhoneAuthSection(
    state: AuthUiState,
    viewModel: AuthViewModel,
    onDismissKeyboard: () -> Unit
) {
    val otpFocusRequester = remember { FocusRequester() }

    if (!state.isAwaitingOTP) {
        Text(
            text = stringResource(R.string.auth_phone_title),
            style = MaterialTheme.typography.titleLarge
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = stringResource(R.string.auth_phone_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))

        OutlinedTextField(
            value = state.phoneNumber,
            onValueChange = viewModel::updatePhoneNumber,
            label = { Text(stringResource(R.string.auth_phone_label)) },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Phone,
                imeAction = ImeAction.Done
            ),
            keyboardActions = KeyboardActions(onDone = {
                onDismissKeyboard()
                viewModel.sendOTP()
            }),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            enabled = !state.isLoading && !state.isGoogleLoading
        )

        if (!state.isGoogleLoading) {
            ErrorText(state.errorMessage)
        }
        Spacer(modifier = Modifier.height(24.dp))

        LoadingOrButton(
            isLoading = state.isLoading,
            label = stringResource(R.string.auth_send_code),
            enabled = !state.isGoogleLoading,
            onClick = viewModel::sendOTP
        )
    } else {
        Text(
            text = stringResource(R.string.auth_enter_otp_title),
            style = MaterialTheme.typography.titleLarge
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = stringResource(R.string.auth_enter_otp_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))

        OutlinedTextField(
            value = state.otpCode,
            onValueChange = { if (it.length <= 6) viewModel.updateOtpCode(it) },
            label = { Text(stringResource(R.string.auth_otp_placeholder)) },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Number,
                imeAction = ImeAction.Done
            ),
            keyboardActions = KeyboardActions(onDone = {
                onDismissKeyboard()
                viewModel.verifyOTP()
            }),
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(otpFocusRequester),
            enabled = !state.isLoading
        )

        LaunchedEffect(Unit) {
            otpFocusRequester.requestFocus()
        }

        ErrorText(state.errorMessage)
        Spacer(modifier = Modifier.height(24.dp))

        LoadingOrButton(
            isLoading = state.isLoading,
            label = stringResource(R.string.auth_verify),
            onClick = viewModel::verifyOTP
        )

        Spacer(modifier = Modifier.height(8.dp))
        TextButton(onClick = viewModel::backToPhoneEntry) {
            Text(stringResource(R.string.auth_use_different_number))
        }
    }
}

@Composable
private fun EmailExpandableSection(
    state: AuthUiState,
    viewModel: AuthViewModel,
    onDismissKeyboard: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    TextButton(
        onClick = { expanded = !expanded },
        modifier = Modifier.fillMaxWidth()
    ) {
        Icon(
            imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
            contentDescription = if (expanded) stringResource(R.string.auth_collapse_email) else stringResource(R.string.auth_expand_email),
            modifier = Modifier.size(20.dp)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = if (expanded) stringResource(R.string.auth_hide_email) else stringResource(R.string.auth_sign_in_email),
            style = MaterialTheme.typography.bodyLarge
        )
    }

    AnimatedVisibility(
        visible = expanded,
        enter = expandVertically(),
        exit = shrinkVertically()
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(8.dp))

            if (state.isSignUp) {
                OutlinedTextField(
                    value = state.displayName,
                    onValueChange = viewModel::updateDisplayName,
                    label = { Text(stringResource(R.string.auth_display_name)) },
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
                label = { Text(stringResource(R.string.auth_email)) },
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
                label = { Text(stringResource(R.string.auth_password)) },
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done
                ),
                keyboardActions = KeyboardActions(onDone = {
                    onDismissKeyboard()
                    viewModel.signInWithEmail()
                }),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isLoading
            )

            // Password strength indicator (sign-up only)
            if (state.isSignUp && state.password.isNotEmpty()) {
                val strength = PasswordStrength.evaluate(state.password)
                val strengthColor = when (strength) {
                    PasswordStrength.WEAK -> MaterialTheme.colorScheme.error
                    PasswordStrength.FAIR -> MaterialTheme.colorScheme.tertiary
                    PasswordStrength.GOOD -> MaterialTheme.colorScheme.secondary
                    PasswordStrength.STRONG -> MaterialTheme.colorScheme.primary
                }
                Column(modifier = Modifier.fillMaxWidth()) {
                    androidx.compose.material3.LinearProgressIndicator(
                        progress = { strength.progress },
                        modifier = Modifier.fillMaxWidth().height(4.dp),
                        color = strengthColor,
                        trackColor = MaterialTheme.colorScheme.surfaceVariant
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = strength.label,
                        style = MaterialTheme.typography.labelSmall,
                        color = strengthColor
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
            }

            if (!state.isSignUp) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(
                        onClick = viewModel::sendPasswordReset,
                        enabled = !state.isResettingPassword
                    ) {
                        if (state.isResettingPassword) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp
                            )
                        } else {
                            Text(
                                stringResource(R.string.auth_forgot_password),
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                }
            }

            state.resetPasswordMessage?.let { msg ->
                Text(
                    text = msg,
                    color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.bodySmall,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(8.dp))
            }

            ErrorText(state.errorMessage)
            Spacer(modifier = Modifier.height(24.dp))

            LoadingOrButton(
                isLoading = state.isLoading,
                label = if (state.isSignUp) stringResource(R.string.auth_create_account) else stringResource(R.string.auth_sign_in),
                onClick = viewModel::signInWithEmail
            )

            Spacer(modifier = Modifier.height(8.dp))
            TextButton(onClick = viewModel::toggleSignUp) {
                Text(
                    if (state.isSignUp) stringResource(R.string.auth_already_have_account)
                    else stringResource(R.string.auth_no_account)
                )
            }
        }
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
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    if (isLoading) {
        CircularProgressIndicator()
    } else {
        Button(
            onClick = onClick,
            modifier = Modifier.fillMaxWidth(),
            enabled = enabled
        ) {
            Text(label)
        }
    }
}
