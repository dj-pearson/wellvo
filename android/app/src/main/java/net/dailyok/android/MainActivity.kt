package net.dailyok.android

import android.content.Intent
import android.net.Uri
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
import androidx.lifecycle.lifecycleScope
import dagger.hilt.android.AndroidEntryPoint
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import javax.inject.Inject
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import net.dailyok.android.ui.navigation.AuthState
import net.dailyok.android.ui.navigation.NotificationContext
import net.dailyok.android.ui.navigation.UserRole
import net.dailyok.android.ui.navigation.toModelRole
import net.dailyok.android.ui.navigation.toNavRole
import net.dailyok.android.ui.navigation.DailyOKNavHost
import net.dailyok.android.ui.theme.DailyOKTheme
import net.dailyok.android.network.ForceUpdateState
import net.dailyok.android.ui.screens.update.ForceUpdateScreen
import net.dailyok.android.viewmodels.AuthViewModel

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    companion object {
        /** "Call Now" on an urgent alert: the receiver to phone. */
        const val EXTRA_CALL_RECEIVER_ID = "call_receiver_id"
        /** "Text" on an alert: the receiver to text (from this phone). */
        const val EXTRA_TEXT_RECEIVER_ID = "text_receiver_id"
        /** The alert's push `type`, which picks the pre-filled words. */
        const val EXTRA_TEXT_ALERT_TYPE = "text_alert_type"
    }

    @Inject
    lateinit var supabase: SupabaseClient

    @Serializable
    private data class ReceiverContact(
        val phone: String? = null,
        @kotlinx.serialization.SerialName("display_name") val displayName: String? = null
    )

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
        handleCallIntent(intent)
        handleTextIntent(intent)
        setContent {
            DailyOKTheme {
                // Below MIN_SUPPORTED_ANDROID_APP_VERSION (GET /app-config or a
                // 426): only the update screen, never the app behind it.
                val updateRequired by ForceUpdateState.required.collectAsState()
                val updateUrl by ForceUpdateState.updateUrl.collectAsState()
                if (updateRequired) {
                    // The splash waits on auth, which the app below would report.
                    androidx.compose.runtime.LaunchedEffect(Unit) { isAuthReady = true }
                    ForceUpdateScreen(updateUrl = updateUrl)
                } else {
                    DailyOKApp(
                        notificationContext = notificationContext,
                        onNotificationHandled = { notificationContext = null },
                        deepLinkInviteToken = pendingInviteToken,
                        onDeepLinkHandled = { pendingInviteToken = null },
                        onAuthReady = { isAuthReady = true }
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Version floor on launch and every return to the app (throttled
        // inside; fails open when offline or the server predates the route).
        lifecycleScope.launch {
            ForceUpdateState.refreshFromServer(
                edgeFunctionsUrl = BuildConfig.EDGE_FUNCTIONS_URL,
                appVersion = BuildConfig.VERSION_NAME
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNotificationIntent(intent)
        handleDeepLinkIntent(intent)
        handleCallIntent(intent)
        handleTextIntent(intent)
    }

    private fun handleCallIntent(intent: Intent?) {
        val receiverId = intent?.getStringExtra(EXTRA_CALL_RECEIVER_ID)
            ?.takeIf { uuidPattern.matches(it) } ?: return
        intent.removeExtra(EXTRA_CALL_RECEIVER_ID)
        val notificationId = intent.getIntExtra("extra_notification_id", -1)
        if (notificationId != -1) {
            androidx.core.app.NotificationManagerCompat.from(this).cancel(notificationId)
        }
        lifecycleScope.launch {
            val phone = try {
                // A cold launch from the notification can get here before the
                // stored session is loaded; as anon, RLS hides the number.
                supabase.auth.awaitInitialization()
                // Numbers this caregiver may see (00067); the users row no
                // longer carries other people's phone.
                net.dailyok.android.network.MemberDirectory
                    .contactNumbers(supabase, null, listOf(receiverId))[receiverId]
            } catch (_: Exception) {
                null
            }
            if (!phone.isNullOrBlank()) {
                startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone")))
            } else {
                android.widget.Toast.makeText(
                    this@MainActivity,
                    "Couldn't find their number. Call them from your contacts.",
                    android.widget.Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    /**
     * "Text" on a missed check-in or help alert: open the SMS app to the
     * receiver with a short note filled in. Nothing is sent until the
     * caregiver taps Send — Daily OK's servers send no texts.
     */
    private fun handleTextIntent(intent: Intent?) {
        val receiverId = intent?.getStringExtra(EXTRA_TEXT_RECEIVER_ID)
            ?.takeIf { uuidPattern.matches(it) } ?: return
        val alertType = intent.getStringExtra(EXTRA_TEXT_ALERT_TYPE)?.take(40)
        intent.removeExtra(EXTRA_TEXT_RECEIVER_ID)
        intent.removeExtra(EXTRA_TEXT_ALERT_TYPE)
        val notificationId = intent.getIntExtra("extra_notification_id", -1)
        if (notificationId != -1) {
            androidx.core.app.NotificationManagerCompat.from(this).cancel(notificationId)
        }
        lifecycleScope.launch {
            val contact = try {
                // Same as "Call Now": wait for the stored session on a cold
                // launch, or RLS hides the number.
                supabase.auth.awaitInitialization()
                val name = supabase.postgrest.from("users")
                    .select(columns = io.github.jan.supabase.postgrest.query.Columns.list("display_name")) {
                        filter { eq("id", receiverId) }
                    }
                    .decodeSingleOrNull<ReceiverContact>()
                    ?.displayName
                // Numbers this caregiver may see (00067).
                val number = net.dailyok.android.network.MemberDirectory
                    .contactNumbers(supabase, null, listOf(receiverId))[receiverId]
                ReceiverContact(phone = number, displayName = name)
            } catch (_: Exception) {
                null
            }
            val phone = contact?.phone?.takeIf { net.dailyok.android.util.FamilyText.dialable(it) != null }
            if (phone != null) {
                val body = net.dailyok.android.util.FamilyText.forAlertType(contact?.displayName.orEmpty(), alertType)
                net.dailyok.android.util.FamilyText.open(this@MainActivity, phone, body)
            } else {
                android.widget.Toast.makeText(
                    this@MainActivity,
                    "Couldn't find their number. Text them from your contacts.",
                    android.widget.Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    private val knownNotificationTypes = setOf(
        "CHECKIN_REQUEST", "URGENT_ALERT", "LOCATION_ALERT", "CHECKIN_REMINDER"
    )

    private val uuidPattern = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    private val hexTokenPattern = Regex("^[0-9a-fA-F]+$")

    private fun handleNotificationIntent(intent: Intent?) {
        val type = intent?.getStringExtra("notification_type") ?: return
        // Validate notification_type against known values
        if (type !in knownNotificationTypes) {
            intent.removeExtra("notification_type")
            return
        }
        // Validate request_id and receiver_id as UUID format
        val requestId = intent.getStringExtra("request_id")?.takeIf { uuidPattern.matches(it) }
        val receiverId = intent.getStringExtra("receiver_id")?.takeIf { uuidPattern.matches(it) }

        notificationContext = NotificationContext(
            type = type,
            requestId = requestId,
            receiverId = receiverId
        )
        intent.removeExtra("notification_type")
        intent.removeExtra("request_id")
        intent.removeExtra("receiver_id")
    }

    private fun handleDeepLinkIntent(intent: Intent?) {
        val data = intent?.data ?: return

        // https://dailyok.net/invite/<token>?code=… (the invite text) and the
        // older https://dailyok.net/invite?token=… form. Only the query form
        // was read, so the links the server now sends were ignored.
        if ((data.host == "dailyok.net" || data.host == "www.dailyok.net") &&
            data.path?.startsWith("/invite") == true
        ) {
            val segments = data.pathSegments
            val token = if (segments.size == 2 && segments[0] == "invite") segments[1]
            else data.getQueryParameter("token")
            if (token != null && isValidInviteToken(token)) {
                pendingInviteToken = token
                intent?.data = null
            }
        }

        // Handle dailyok://invite?token=<token>
        if (data.scheme == "dailyok" && data.host == "invite") {
            val token = data.getQueryParameter("token")
            if (token != null && isValidInviteToken(token)) {
                pendingInviteToken = token
                intent?.data = null
            }
        }
    }

    private fun isValidInviteToken(token: String): Boolean {
        return token.length <= 500 && hexTokenPattern.matches(token)
    }
}

@Composable
fun DailyOKApp(
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
    val membership by authViewModel.membership.collectAsState()
    val setupChoice by authViewModel.setupChoice.collectAsState()

    // Route by actual family membership (AuthViewModel.resolveMembership), not
    // users.role, which is "owner" for every account until a join rewrites it.
    val userRole: UserRole? = (membership as? net.dailyok.android.viewmodels.Membership.Member)
        ?.role?.toNavRole()
    val membershipResolved = membership is net.dailyok.android.viewmodels.Membership.None
    val membershipFailed = membership is net.dailyok.android.viewmodels.Membership.Failed

    // An invite link is for someone with no family. Drop it once we know this
    // user already has one, and on sign-out, so it can't be redeemed later for
    // whoever signs in next. (A cold start from a link goes Loading ->
    // Unauthenticated and keeps its token for the sign-in that follows.)
    var wasAuthenticated by androidx.compose.runtime.remember { mutableStateOf(false) }
    androidx.compose.runtime.LaunchedEffect(authState, membership) {
        if (authState is AuthState.Authenticated) wasAuthenticated = true
        if (authState is AuthState.Unauthenticated && wasAuthenticated) {
            wasAuthenticated = false
            onDeepLinkHandled()
        }
        if (membership is net.dailyok.android.viewmodels.Membership.Member && deepLinkInviteToken != null) {
            onDeepLinkHandled()
        }
    }

    val hasAutoJoin = pendingAutoJoin != null
    // A link's token, or an invite matching this phone number (auto-join
    // preview), goes to ReceiverOnboarding, which shows the family first and
    // joins only on "Join". Nothing has been joined yet in either case.
    val showReceiverOnboarding = deepLinkInviteToken != null || hasAutoJoin

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

    // An account made with the retired phone sign-in is asked to add an email
    // while its session still works (dismissible; asked again next launch).
    if (authState is AuthState.Authenticated && !uiState.biometricLocked) {
        net.dailyok.android.ui.screens.auth.AddEmailDialog(state = uiState, viewModel = authViewModel)
    }

    val appPrefs: net.dailyok.android.viewmodels.AppPreferencesViewModel = hiltViewModel()
    val hapticsEnabled by appPrefs.hapticsEnabled.collectAsState()

    androidx.compose.runtime.CompositionLocalProvider(
        net.dailyok.android.ui.theme.LocalDailyOKHapticsEnabled provides hapticsEnabled
    ) {
        Scaffold(modifier = modifier.fillMaxSize()) { innerPadding ->
            DailyOKNavHost(
                navController = navController,
                authState = authState,
                userRole = userRole,
                isOnboarding = setupChoice == net.dailyok.android.viewmodels.SetupChoice.OwnerSetup,
                pendingInviteToken = deepLinkInviteToken,
                showPairingCode = setupChoice == net.dailyok.android.viewmodels.SetupChoice.CodeEntry,
                notificationContext = notificationContext,
                onNotificationHandled = onNotificationHandled,
                showReceiverOnboarding = showReceiverOnboarding,
                membershipResolved = membershipResolved,
                membershipFailed = membershipFailed,
                onJoined = { role ->
                    authViewModel.onJoined(role.toModelRole())
                    onDeepLinkHandled()
                },
                onJoinCancelled = {
                    authViewModel.onJoinCancelled()
                    onDeepLinkHandled()
                },
                onChooseCodeEntry = authViewModel::chooseCodeEntry,
                onChooseOwnerSetup = authViewModel::chooseOwnerSetup,
                onBackToChoice = authViewModel::clearSetupChoice,
                onJoinedResolveRole = {
                    authViewModel.onJoinedResolveRole()
                    onDeepLinkHandled()
                },
                onLeaveOwnerSetup = authViewModel::leaveOwnerSetup,
                onRetryMembership = authViewModel::retryMembership,
                onSignOut = authViewModel::signOut,
                onMembershipChanged = authViewModel::onMembershipChanged,
                pendingAutoJoin = pendingAutoJoin,
                modifier = Modifier.padding(innerPadding)
            )
        }
    }
}
