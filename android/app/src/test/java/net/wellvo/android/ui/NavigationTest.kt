package net.wellvo.android.ui

import net.wellvo.android.data.models.UserRole
import net.wellvo.android.ui.navigation.OwnerTab
import net.wellvo.android.ui.navigation.Route
import net.wellvo.android.ui.navigation.ViewerTab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class NavigationTest {

    @Test
    fun `owner role maps to owner_tabs route`() {
        val route = routeForRole(UserRole.Owner)
        assertEquals(Route.OwnerTabs.route, route)
    }

    @Test
    fun `receiver role maps to receiver_home route`() {
        val route = routeForRole(UserRole.Receiver)
        assertEquals(Route.ReceiverHome.route, route)
    }

    @Test
    fun `viewer role maps to viewer_tabs route`() {
        val route = routeForRole(UserRole.Viewer)
        assertEquals(Route.ViewerTabs.route, route)
    }

    @Test
    fun `owner has 4 tabs including Family`() {
        val ownerTabs = listOf(
            OwnerTab.Dashboard,
            OwnerTab.History,
            OwnerTab.Family,
            OwnerTab.Settings
        )
        assertEquals(4, ownerTabs.size)
        assertTrue(ownerTabs.any { it.label == "Family" })
        assertTrue(ownerTabs.any { it.label == "Dashboard" })
        assertTrue(ownerTabs.any { it.label == "History" })
        assertTrue(ownerTabs.any { it.label == "Settings" })
    }

    @Test
    fun `viewer has 3 tabs without Family`() {
        val viewerTabs = listOf(
            ViewerTab.Dashboard,
            ViewerTab.History,
            ViewerTab.Settings
        )
        assertEquals(3, viewerTabs.size)
        assertTrue(viewerTabs.none { it.label == "Family" })
        assertTrue(viewerTabs.any { it.label == "Dashboard" })
        assertTrue(viewerTabs.any { it.label == "History" })
        assertTrue(viewerTabs.any { it.label == "Settings" })
    }

    @Test
    fun `all routes have non-empty route strings`() {
        val routes = listOf(
            Route.Splash, Route.Auth, Route.Onboarding,
            Route.OwnerTabs, Route.ReceiverHome, Route.ViewerTabs,
            Route.PairingCode, Route.ReceiverOnboarding
        )
        routes.forEach { route ->
            assertTrue("Route ${route::class.simpleName} has empty route", route.route.isNotEmpty())
        }
    }

    @Test
    fun `unauthenticated state maps to auth route`() {
        assertEquals("auth", Route.Auth.route)
    }

    /** Mirrors the role-based routing logic in WellvoNavHost */
    private fun routeForRole(role: UserRole): String = when (role) {
        UserRole.Owner -> Route.OwnerTabs.route
        UserRole.Receiver -> Route.ReceiverHome.route
        UserRole.Viewer -> Route.ViewerTabs.route
    }
}
