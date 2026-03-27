package net.wellvo.android.ui.screens.viewer

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
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
import net.wellvo.android.ui.screens.owner.DashboardScreen
import net.wellvo.android.ui.screens.owner.HistoryScreen
import net.wellvo.android.viewmodels.DashboardViewModel
import net.wellvo.android.viewmodels.HistoryViewModel
import net.wellvo.android.viewmodels.SettingsViewModel

private data class ViewerTabItem(
    val label: String,
    val icon: ImageVector
)

private val viewerTabs = listOf(
    ViewerTabItem("Dashboard", Icons.Default.Home),
    ViewerTabItem("History", Icons.Default.DateRange),
    ViewerTabItem("Settings", Icons.Default.Settings),
)

@Composable
fun ViewerTabsScreen(userId: String = "") {
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }

    Scaffold(
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.onSurface
            ) {
                viewerTabs.forEachIndexed { index, tab ->
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
            label = "viewer_tab_content"
        ) { tab ->
            when (tab) {
                0 -> {
                    val dashboardViewModel: DashboardViewModel = hiltViewModel()
                    DashboardScreen(
                        viewModel = dashboardViewModel,
                        userId = userId,
                        modifier = Modifier.padding(innerPadding),
                        isViewer = true
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
                else -> {
                    val settingsViewModel: SettingsViewModel = hiltViewModel()
                    ViewerSettingsScreen(
                        viewModel = settingsViewModel,
                        userId = userId,
                        modifier = Modifier.padding(innerPadding)
                    )
                }
            }
        }
    }
}
