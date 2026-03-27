package net.wellvo.android.ui.screens.owner

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import net.wellvo.android.viewmodels.DashboardViewModel

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
            NavigationBar {
                ownerTabs.forEachIndexed { index, tab ->
                    NavigationBarItem(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) }
                    )
                }
            }
        }
    ) { innerPadding ->
        when (selectedTab) {
            0 -> {
                val dashboardViewModel: DashboardViewModel = hiltViewModel()
                DashboardScreen(
                    viewModel = dashboardViewModel,
                    userId = userId,
                    modifier = Modifier.padding(innerPadding)
                )
            }
            else -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = ownerTabs[selectedTab].label,
                        style = MaterialTheme.typography.headlineMedium
                    )
                }
            }
        }
    }
}
