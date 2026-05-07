import SwiftUI

// Note: We intentionally keep the platform-default TabView for the top-level
// owner tabs (Dashboard, History, Family, Settings). The custom
// FloatingBottomNav component (Views/Components/FloatingBottomNav.swift)
// remains available for sub-navigation surfaces — but the platform tab bar
// gives us free VoiceOver tab traits, safe-area + gesture-edge handling,
// Dynamic Type behavior, and deep-link routing through AppState.selectedTab
// without bespoke re-implementation. See US-UX028 for the full decision rationale.
struct OwnerTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "heart.text.square")
                }
                .tag(AppState.AppTab.dashboard)
                .accessibilityLabel("Dashboard tab")

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }
                .tag(AppState.AppTab.history)
                .accessibilityLabel("History tab")

            FamilyView()
                .tabItem {
                    Label("Family", systemImage: "person.3")
                }
                .tag(AppState.AppTab.family)
                .accessibilityLabel("Family tab")

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppState.AppTab.settings)
                .accessibilityLabel("Settings tab")
        }
        .tint(.green)
    }
}
