package net.wellvo.android.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import net.wellvo.android.ui.screens.auth.AuthScreen
import net.wellvo.android.ui.screens.onboarding.OnboardingScreen
import net.wellvo.android.ui.screens.onboarding.PairingCodeScreen
import net.wellvo.android.ui.screens.onboarding.ReceiverOnboardingScreen
import net.wellvo.android.ui.screens.owner.OwnerTabsScreen
import net.wellvo.android.ui.screens.receiver.ReceiverHomeScreen
import net.wellvo.android.ui.screens.splash.SplashScreen
import net.wellvo.android.ui.screens.viewer.ViewerTabsScreen

@Composable
fun WellvoNavHost(
    navController: NavHostController,
    authState: AuthState,
    userRole: UserRole?,
    isOnboarding: Boolean,
    pendingInviteToken: String?,
    showPairingCode: Boolean,
    modifier: Modifier = Modifier
) {
    NavHost(
        navController = navController,
        startDestination = Route.Splash.route,
        modifier = modifier
    ) {
        composable(Route.Splash.route) {
            SplashScreen()
        }
        composable(Route.Auth.route) {
            AuthScreen()
        }
        composable(Route.Onboarding.route) {
            OnboardingScreen(
                onComplete = {
                    navController.navigate(Route.OwnerTabs.route) {
                        popUpTo(0) { inclusive = true }
                        launchSingleTop = true
                    }
                }
            )
        }
        composable(Route.OwnerTabs.route) {
            val userId = (authState as? AuthState.Authenticated)?.user?.id ?: ""
            OwnerTabsScreen(userId = userId)
        }
        composable(Route.ReceiverHome.route) {
            ReceiverHomeScreen()
        }
        composable(Route.ViewerTabs.route) {
            ViewerTabsScreen()
        }
        composable(Route.PairingCode.route) {
            PairingCodeScreen(
                onComplete = {
                    navController.navigate(Route.ReceiverHome.route) {
                        popUpTo(0) { inclusive = true }
                        launchSingleTop = true
                    }
                }
            )
        }
        composable(Route.ReceiverOnboarding.route) {
            ReceiverOnboardingScreen(
                inviteToken = pendingInviteToken,
                onComplete = {
                    navController.navigate(Route.ReceiverHome.route) {
                        popUpTo(0) { inclusive = true }
                        launchSingleTop = true
                    }
                }
            )
        }
    }

    val targetRoute = when (authState) {
        is AuthState.Loading -> Route.Splash.route
        is AuthState.Unauthenticated -> Route.Auth.route
        is AuthState.Authenticated -> when {
            pendingInviteToken != null -> Route.ReceiverOnboarding.route
            showPairingCode -> Route.PairingCode.route
            isOnboarding -> Route.Onboarding.route
            else -> when (userRole) {
                UserRole.Receiver -> Route.ReceiverHome.route
                UserRole.Viewer -> Route.ViewerTabs.route
                else -> Route.OwnerTabs.route
            }
        }
    }

    val currentRoute = navController.currentBackStackEntry?.destination?.route
    if (currentRoute != targetRoute) {
        navController.navigate(targetRoute) {
            popUpTo(0) { inclusive = true }
            launchSingleTop = true
        }
    }
}
