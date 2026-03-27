package net.wellvo.android

import android.content.Intent
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.compose.rememberNavController
import dagger.hilt.android.AndroidEntryPoint
import net.wellvo.android.ui.navigation.AuthState
import net.wellvo.android.ui.navigation.NotificationContext
import net.wellvo.android.ui.navigation.UserRole
import net.wellvo.android.ui.navigation.WellvoNavHost
import net.wellvo.android.ui.theme.WellvoTheme
import net.wellvo.android.viewmodels.AuthViewModel

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    private var notificationContext by mutableStateOf<NotificationContext?>(null)
    private var pendingInviteToken by mutableStateOf<String?>(null)
    private var isAuthReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        super.onCreate(savedInstanceState)

        // Hold splash screen until auth state resolves
        splashScreen.setKeepOnScreenCondition { !isAuthReady }

        enableEdgeToEdge()
        handleNotificationIntent(intent)
        handleDeepLinkIntent(intent)
        setContent {
            WellvoTheme {
                WellvoApp(
                    notificationContext = notificationContext,
                    onNotificationHandled = { notificationContext = null },
                    deepLinkInviteToken = pendingInviteToken,
                    onDeepLinkHandled = { pendingInviteToken = null },
                    onAuthReady = { isAuthReady = true }
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNotificationIntent(intent)
        handleDeepLinkIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        val type = intent?.getStringExtra("notification_type") ?: return
        notificationContext = NotificationContext(
            type = type,
            requestId = intent.getStringExtra("request_id"),
            receiverId = intent.getStringExtra("receiver_id")
        )
        intent.removeExtra("notification_type")
        intent.removeExtra("request_id")
        intent.removeExtra("receiver_id")
    }

    private fun handleDeepLinkIntent(intent: Intent?) {
        val data = intent?.data ?: return

        // Handle https://wellvo.net/invite?token=<token>
        if (data.host == "wellvo.net" && data.path?.startsWith("/invite") == true) {
            val token = data.getQueryParameter("token")
            if (token != null) {
                pendingInviteToken = token
                intent?.data = null
            }
        }

        // Handle wellvo://invite?token=<token>
        if (data.scheme == "wellvo" && data.host == "invite") {
            val token = data.getQueryParameter("token")
            if (token != null) {
                pendingInviteToken = token
                intent?.data = null
            }
        }
    }
}

@Composable
fun WellvoApp(
    modifier: Modifier = Modifier,
    notificationContext: NotificationContext? = null,
    onNotificationHandled: () -> Unit = {},
    deepLinkInviteToken: String? = null,
    onDeepLinkHandled: () -> Unit = {},
    onAuthReady: () -> Unit = {}
) {
    val navController = rememberNavController()
    val authViewModel: AuthViewModel = hiltViewModel()
    val authState by authViewModel.authState.collectAsState()
    val uiState by authViewModel.uiState.collectAsState()

    // Signal splash screen dismissal when auth state resolves
    androidx.compose.runtime.LaunchedEffect(authState) {
        if (authState !is AuthState.Loading) {
            onAuthReady()
        }
    }

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

    // Deep link invite token takes priority over auto-join
    val effectiveInviteToken = deepLinkInviteToken
        ?: if (hasAutoJoin) pendingAutoJoin?.familyId else null

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
            isOnboarding = isNewUser && !hasAutoJoin && deepLinkInviteToken == null,
            pendingInviteToken = effectiveInviteToken,
            showPairingCode = false,
            notificationContext = notificationContext,
            onNotificationHandled = {
                onNotificationHandled()
                onDeepLinkHandled()
            },
            modifier = Modifier.padding(innerPadding)
        )
    }
}
