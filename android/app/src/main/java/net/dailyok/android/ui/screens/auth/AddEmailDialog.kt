package net.dailyok.android.ui.screens.auth

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import net.dailyok.android.viewmodels.AddEmailStage
import net.dailyok.android.viewmodels.AuthUiState
import net.dailyok.android.viewmodels.AuthViewModel

/**
 * Asks an account made with the retired phone sign-in to add an email while
 * its session still works: once signed out, it has no other way back in.
 *
 * Dismissible ("Not now", back, tap outside) and asked again next launch — it
 * can land over a receiver's I'm OK screen and must never stand in their way.
 * Confirms with the 6-digit code in the email; tapping the link in the email
 * also works, and "I tapped the link" re-checks.
 */
@Composable
fun AddEmailDialog(state: AuthUiState, viewModel: AuthViewModel) {
    val stage = state.addEmailStage
    if (stage == AddEmailStage.Hidden) return

    AlertDialog(
        onDismissRequest = {
            if (stage == AddEmailStage.Done) viewModel.finishAddEmail() else viewModel.deferAddEmail()
        },
        title = {
            Text(
                when (stage) {
                    AddEmailStage.Done -> "Email added"
                    AddEmailStage.EnterCode -> "Check your email"
                    else -> "Add an email so you can always sign in"
                }
            )
        },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                when (stage) {
                    AddEmailStage.EnterEmail, AddEmailStage.Hidden -> {
                        Text(
                            "Daily OK no longer signs in with text-message codes. Add an email now, " +
                                "and you can sign in with it if you ever get a new phone or sign out.",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        OutlinedTextField(
                            value = state.addEmailAddress,
                            onValueChange = viewModel::updateAddEmailAddress,
                            label = { Text("Email") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Email,
                                imeAction = ImeAction.Send
                            ),
                            enabled = !state.isAddingEmail,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    AddEmailStage.EnterCode -> {
                        Text(
                            "Enter the 6-digit code we emailed to ${state.addEmailAddress}.",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        OutlinedTextField(
                            value = state.addEmailCode,
                            onValueChange = viewModel::updateAddEmailCode,
                            label = { Text("6-digit code") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.NumberPassword,
                                imeAction = ImeAction.Done
                            ),
                            enabled = !state.isAddingEmail,
                            modifier = Modifier.fillMaxWidth()
                        )
                        TextButton(
                            onClick = viewModel::checkAddedEmailByLink,
                            enabled = !state.isAddingEmail
                        ) { Text("I tapped the link in the email") }
                        TextButton(
                            onClick = viewModel::editAddEmailAddress,
                            enabled = !state.isAddingEmail
                        ) { Text("Use a different email") }
                    }
                    AddEmailStage.Done -> {
                        Text(
                            "You can now sign in with ${state.addEmailAddress}. Use \"Forgot password?\" " +
                                "on the sign-in screen to set a password if you need one.",
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
                state.addEmailError?.let {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            when (stage) {
                AddEmailStage.Done -> Button(onClick = viewModel::finishAddEmail) { Text("Done") }
                AddEmailStage.EnterCode -> Button(
                    onClick = viewModel::confirmAddEmailCode,
                    enabled = !state.isAddingEmail && state.addEmailCode.length == 6
                ) {
                    if (state.isAddingEmail) CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    else Text("Confirm")
                }
                else -> Button(
                    onClick = viewModel::sendAddEmailCode,
                    enabled = !state.isAddingEmail
                ) {
                    if (state.isAddingEmail) CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    else Text("Send code")
                }
            }
        },
        dismissButton = {
            if (stage != AddEmailStage.Done) {
                TextButton(onClick = viewModel::deferAddEmail) { Text("Not now") }
            }
        }
    )
}
