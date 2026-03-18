import SwiftUI

/// Read-only tab view for Viewers — same dashboard as Owner but no edit controls.
struct ViewerTabView: View {
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

            ViewerSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppState.AppTab.settings)
        }
        .tint(.green)
    }
}

/// Minimal settings for Viewers — account info and sign out only.
struct ViewerSettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let user = authViewModel.currentUser {
                        HStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Text(String(user.displayName.prefix(1)).uppercased())
                                        .fontWeight(.bold)
                                        .foregroundStyle(.green)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.body)
                                Text(user.email ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Text("Role")
                            Spacer()
                            Text("Viewer")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link("Privacy Policy", destination: URL(string: "https://wellvo.net/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://wellvo.net/terms")!)
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        Task { await authViewModel.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
