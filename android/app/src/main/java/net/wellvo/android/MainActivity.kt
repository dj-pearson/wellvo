package net.wellvo.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.compose.rememberNavController
import dagger.hilt.android.AndroidEntryPoint
import net.wellvo.android.ui.navigation.AuthState
import net.wellvo.android.ui.navigation.UserRole
import net.wellvo.android.ui.navigation.WellvoNavHost
import net.wellvo.android.ui.theme.WellvoTheme
import net.wellvo.android.viewmodels.AuthViewModel

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            WellvoTheme {
                WellvoApp()
            }
        }
    }
}

@Composable
fun WellvoApp(modifier: Modifier = Modifier) {
    val navController = rememberNavController()
    val authViewModel: AuthViewModel = hiltViewModel()
    val authState by authViewModel.authState.collectAsState()
    val uiState by authViewModel.uiState.collectAsState()

    val pendingAutoJoin by authViewModel.pendingAutoJoin.collectAsState()

    val userRole: UserRole? = when (val state = authState) {
        is AuthState.Authenticated -> when (state.user.role) {
            net.wellvo.android.data.models.UserRole.Owner -> UserRole.Owner
            net.wellvo.android.data.models.UserRole.Receiver -> UserRole.Receiver
            net.wellvo.android.data.models.UserRole.Viewer -> UserRole.Viewer
        }
        else -> null
    }

    val isNewUser = authState is AuthState.Authenticated &&
        (authState as AuthState.Authenticated).user.displayName.isBlank()

    val hasAutoJoin = pendingAutoJoin != null

    if (uiState.showReauthPrompt) {
        AlertDialog(
            onDismissRequest = { authViewModel.dismissReauthPrompt() },
            title = { Text("Session Expired") },
            text = { Text("Your session has expired. Please sign in again.") },
            confirmButton = {
                TextButton(onClick = { authViewModel.dismissReauthPrompt() }) {
                    Text("OK")
                }
            }
        )
    }

    Scaffold(modifier = modifier.fillMaxSize()) { innerPadding ->
        WellvoNavHost(
            navController = navController,
            authState = authState,
            userRole = userRole,
            isOnboarding = isNewUser && !hasAutoJoin,
            pendingInviteToken = if (hasAutoJoin) pendingAutoJoin?.familyId else null,
            showPairingCode = false,
            modifier = Modifier.padding(innerPadding)
        )
    }
}
