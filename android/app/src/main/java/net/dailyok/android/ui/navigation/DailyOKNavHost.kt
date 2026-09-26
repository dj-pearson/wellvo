package net.dailyok.android.ui.navigation

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import net.dailyok.android.ui.screens.auth.AuthScreen
import androidx.activity.compose.BackHandler
import net.dailyok.android.ui.screens.onboarding.GetStartedScreen
import net.dailyok.android.ui.screens.onboarding.MembershipLoadFailedScreen
import net.dailyok.android.ui.screens.onboarding.OnboardingScreen
import net.dailyok.android.ui.screens.onboarding.PairingCodeScreen
import net.dailyok.android.ui.screens.onboarding.ReceiverOnboardingScreen
import net.dailyok.android.ui.screens.owner.OwnerTabsScreen
import net.dailyok.android.ui.screens.receiver.ReceiverHomeScreen
import net.dailyok.android.ui.screens.splash.SplashScreen
import net.dailyok.android.ui.screens.viewer.ViewerTabsScreen

@Composable
fun DailyOKNavHost(
    navController: NavHostController,
    authState: AuthState,
    userRole: UserRole?,
    isOnboarding: Boolean,
    pendingInviteToken: String?,
    showPairingCode: Boolean,
    modifier: Modifier = Modifier,
    notificationContext: NotificationContext? = null,
    onNotificationHandled: () -> Unit = {},
    /** Joining (link or phone match) in progress for a user with no family. */
    showReceiverOnboarding: Boolean = pendingInviteToken != null,
    /** The server confirmed this user belongs to no family. */
    membershipResolved: Boolean = true,
    /** The membership lookup failed and no role is cached. */
    membershipFailed: Boolean = false,
    onJoined: (UserRole) -> Unit = {},
    onJoinCancelled: () -> Unit = {},
    onChooseCodeEntry: () -> Unit = {},
    onChooseOwnerSetup: () -> Unit = {},
    onBackToChoice: () -> Unit = {},
    onRetryMembership: () -> Unit = {},
    onSignOut: () -> Unit = {}
) {
    val transitionDuration = 300

    NavHost(
        navController = navController,
        startDestination = Route.Splash.route,
        modifier = modifier,
        enterTransition = {
            fadeIn(animationSpec = tween(transitionDuration)) +
                slideIntoContainer(AnimatedContentTransitionScope.SlideDirection.Start, tween(transitionDuration))
        },
        exitTransition = {
            fadeOut(animationSpec = tween(transitionDuration)) +
                slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.Start, tween(transitionDuration))
        },
        popEnterTransition = {
            fadeIn(animationSpec = tween(transitionDuration)) +
                slideIntoContainer(AnimatedContentTransitionScope.SlideDirection.End, tween(transitionDuration))
        },
        popExitTransition = {
            fadeOut(animationSpec = tween(transitionDuration)) +
                slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.End, tween(transitionDuration))
        }
    ) {
        composable(
            Route.Splash.route,
            enterTransition = { fadeIn(tween(transitionDuration)) },
            exitTransition = { fadeOut(tween(transitionDuration)) }
        ) {
            SplashScreen()
        }
        composable(
            Route.Auth.route,
            enterTransition = { fadeIn(tween(transitionDuration)) },
            exitTransition = { fadeOut(tween(transitionDuration)) }
        ) {
            AuthScreen()
        }
        composable(Route.Onboarding.route) {
            // System back on the first step returns to the start choice (the
            // screen's own handlers take precedence on later steps).
            BackHandler { onBackToChoice() }
            OnboardingScreen(
                // Routing follows the role: the family exists now, so this user
                // owns it. Navigating directly raced the route recomputation.
                onComplete = { onJoined(UserRole.Owner) }
            )
        }
        composable(Route.GetStarted.route) {
            GetStartedScreen(
                onInvited = onChooseCodeEntry,
                onSetUpFamily = onChooseOwnerSetup,
                onSignOut = onSignOut
            )
        }
        composable(Route.MembershipFailed.route) {
            MembershipLoadFailedScreen(onRetry = onRetryMembership)
        }
        composable(Route.OwnerTabs.route) {
            val userId = (authState as? AuthState.Authenticated)?.user?.id ?: ""
            OwnerTabsScreen(userId = userId)
        }
        composable(Route.ReceiverHome.route) {
            ReceiverHomeScreen()
        }
        composable(Route.ViewerTabs.route) {
            val userId = (authState as? AuthState.Authenticated)?.user?.id ?: ""
            ViewerTabsScreen(userId = userId)
        }
        composable(Route.PairingCode.route) {
            BackHandler { onBackToChoice() }
            PairingCodeScreen(
                onComplete = { onJoined(UserRole.Receiver) }
            )
        }
        composable(Route.ReceiverOnboarding.route) {
            ReceiverOnboardingScreen(
                inviteToken = pendingInviteToken,
                onComplete = { onJoined(UserRole.Receiver) },
                onCancel = onJoinCancelled
            )
        }
    }

    val targetRoute = when (authState) {
        is AuthState.Loading -> Route.Splash.route
        is AuthState.Unauthenticated -> Route.Auth.route
        // By actual membership. "Anything not receiver or viewer is an owner"
        // sent receivers whose join hadn't finished — and anyone whose role
        // lookup failed offline — to the owner tabs.
        is AuthState.Authenticated -> when {
            showReceiverOnboarding && userRole == null && membershipResolved -> Route.ReceiverOnboarding.route
            showPairingCode -> Route.PairingCode.route
            isOnboarding -> Route.Onboarding.route
            userRole == UserRole.Receiver -> Route.ReceiverHome.route
            userRole == UserRole.Viewer -> Route.ViewerTabs.route
            userRole == UserRole.Owner -> Route.OwnerTabs.route
            membershipFailed -> Route.MembershipFailed.route
            membershipResolved -> Route.GetStarted.route
            else -> Route.Splash.route
        }
    }

    val currentRoute = navController.currentBackStackEntry?.destination?.route
    if (currentRoute != targetRoute) {
        navController.navigate(targetRoute) {
            popUpTo(0) { inclusive = true }
            launchSingleTop = true
        }
    }

    // Handle notification deep routing after auth is resolved
    LaunchedEffect(notificationContext, authState) {
        if (notificationContext == null || authState !is AuthState.Authenticated) return@LaunchedEffect

        val deepRoute = when (notificationContext.type) {
            "CHECKIN_REQUEST" -> Route.ReceiverHome.route
            "URGENT_ALERT" -> Route.OwnerTabs.route
            "LOCATION_ALERT" -> Route.OwnerTabs.route
            else -> null
        }

        if (deepRoute != null && navController.currentBackStackEntry?.destination?.route != deepRoute) {
            navController.navigate(deepRoute) {
                popUpTo(0) { inclusive = true }
                launchSingleTop = true
            }
        }

        onNotificationHandled()
    }
}
