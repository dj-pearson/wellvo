import SwiftUI

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
