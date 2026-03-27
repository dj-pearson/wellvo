package net.wellvo.android.ui.navigation

sealed class Route(val route: String) {
    data object Splash : Route("splash")
    data object Auth : Route("auth")
    data object Onboarding : Route("onboarding")
    data object OwnerTabs : Route("owner_tabs")
    data object ReceiverHome : Route("receiver_home")
    data object ViewerTabs : Route("viewer_tabs")
    data object PairingCode : Route("pairing_code")
    data object ReceiverOnboarding : Route("receiver_onboarding")
}

sealed class OwnerTab(val route: String, val label: String, val icon: String) {
    data object Dashboard : OwnerTab("owner_dashboard", "Dashboard", "dashboard")
    data object History : OwnerTab("owner_history", "History", "history")
    data object Family : OwnerTab("owner_family", "Family", "family")
    data object Settings : OwnerTab("owner_settings", "Settings", "settings")
}

sealed class ViewerTab(val route: String, val label: String, val icon: String) {
    data object Dashboard : ViewerTab("viewer_dashboard", "Dashboard", "dashboard")
    data object History : ViewerTab("viewer_history", "History", "history")
    data object Settings : ViewerTab("viewer_settings", "Settings", "settings")
}
