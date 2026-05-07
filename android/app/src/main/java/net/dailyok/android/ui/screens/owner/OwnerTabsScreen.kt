package net.dailyok.android.ui.screens.owner

// Note: We intentionally keep the platform-default Material3 NavigationBar for
// the top-level owner tabs (Dashboard, History, Family, Settings). The custom
// FloatingBottomNav component (ui/components/FloatingBottomNav.kt) remains
// available for sub-navigation surfaces — but Material3 NavigationBar gives
// us free TalkBack tab semantics, system-bar inset handling, predictive-back
// integration, and Dynamic Type / large-text scaling without bespoke
// re-implementation. See US-UX028 for the full decision rationale.

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.hilt.navigation.compose.hiltViewModel
import net.dailyok.android.viewmodels.DashboardViewModel
import net.dailyok.android.viewmodels.FamilyViewModel
import net.dailyok.android.viewmodels.HistoryViewModel
import net.dailyok.android.viewmodels.SettingsViewModel

private data class OwnerTabItem(
    val label: String,
    val icon: ImageVector
)

private val ownerTabs = listOf(
    OwnerTabItem("Dashboard", Icons.Default.Home),
    OwnerTabItem("History", Icons.Default.DateRange),
    OwnerTabItem("Family", Icons.Default.People),
    OwnerTabItem("Settings", Icons.Default.Settings),
)

@Composable
fun OwnerTabsScreen(userId: String = "") {
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }

    Scaffold(
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.onSurface
            ) {
                ownerTabs.forEachIndexed { index, tab ->
                    NavigationBarItem(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = MaterialTheme.colorScheme.primary,
                            selectedTextColor = MaterialTheme.colorScheme.primary,
                            indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    )
                }
            }
        }
    ) { innerPadding ->
        AnimatedContent(
            targetState = selectedTab,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "owner_tab_content"
        ) { tab ->
            when (tab) {
                0 -> {
                    val dashboardViewModel: DashboardViewModel = hiltViewModel()
                    DashboardScreen(
                        viewModel = dashboardViewModel,
                        userId = userId,
                        modifier = Modifier.padding(innerPadding)
                    )
                }
                1 -> {
                    val historyViewModel: HistoryViewModel = hiltViewModel()
                    HistoryScreen(
                        viewModel = historyViewModel,
                        userId = userId,
                        modifier = Modifier.padding(innerPadding)
                    )
                }
                2 -> {
                    val familyViewModel: FamilyViewModel = hiltViewModel()
                    FamilyScreen(
                        viewModel = familyViewModel,
                        userId = userId,
                        modifier = Modifier.padding(innerPadding)
                    )
                }
                else -> {
                    val settingsViewModel: SettingsViewModel = hiltViewModel()
                    SettingsScreen(
                        viewModel = settingsViewModel,
                        userId = userId,
                        modifier = Modifier.padding(innerPadding)
                    )
                }
            }
        }
    }
}
