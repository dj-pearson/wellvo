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

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }
                .tag(AppState.AppTab.history)

            FamilyView()
                .tabItem {
                    Label("Family", systemImage: "person.3")
                }
                .tag(AppState.AppTab.family)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppState.AppTab.settings)
        }
        .tint(.green)
    }
}
