package net.dailyok.android.ui.screens.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * First screen for a signed-in user who belongs to no family yet.
 *
 * Routing used to fall back to the owner tabs for anyone not marked receiver
 * or viewer — and users.role defaults to "owner" — so a receiver whose invite
 * hadn't matched landed on an owner dashboard. Setup has two starts; ask.
 */
@Composable
fun GetStartedScreen(
    onInvited: () -> Unit,
    onSetUpFamily: () -> Unit,
    onSignOut: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "Welcome to Daily OK",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = "How will you use it?",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(32.dp))

        Button(
            onClick = onInvited,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("I was invited", fontWeight = FontWeight.SemiBold)
                Text(
                    "Someone sent me a text with a setup code",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        OutlinedButton(
            onClick = onSetUpFamily,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Set up check-ins for someone", fontWeight = FontWeight.SemiBold)
                Text(
                    "A parent, grandparent, teen or friend",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }

        Spacer(Modifier.height(32.dp))
        TextButton(onClick = onSignOut) { Text("Sign out") }
    }
}

/** Shown when the membership lookup fails and no role is cached. */
@Composable
fun MembershipLoadFailedScreen(onRetry: () -> Unit, onSignOut: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "Can't reach Daily OK",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = "Check your internet connection and try again.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(24.dp))
        Button(onClick = onRetry) { Text("Try Again") }
        Spacer(Modifier.height(8.dp))
        TextButton(onClick = onSignOut) { Text("Sign out") }
    }
}
