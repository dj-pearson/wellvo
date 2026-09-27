import SwiftUI
import StoreKit

/// Read-only tab view for Viewers — same dashboard as Owner but no edit controls.
///
/// Note: Like OwnerTabView, we intentionally keep the platform-default TabView
/// rather than the custom FloatingBottomNav component. See US-UX028 for the
/// keep-platform-bar decision rationale.
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
        .onAppear {
            // selectedTab is shared with OwnerTabView; viewers have no Family tab,
            // so a leftover .family selection (e.g. right after a role change from
            // owner) would match no tab. Fall back to Dashboard.
            if appState.selectedTab == .family { appState.selectedTab = .dashboard }
        }
    }
}

/// Settings for co-caregivers (viewers).
///
/// Used to be account info and Sign Out only. A co-caregiver — including the
/// ex-owner after handing the family over — had no way to delete their
/// account, export their data, see whether alerts can reach them, lock the app,
/// or reach Manage Subscription for a plan they may still be paying for.
struct ViewerSettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSignOutConfirmation = false
    @State private var showManageSubscriptions = false
    @State private var family: Family?

    private var storeRelation: PlanSummary.StoreRelation {
        guard subscriptionService.hasLoadedEntitlements else { return .consistent }
        return PlanSummary.storeRelation(
            storeTier: subscriptionService.currentTier,
            family: family,
            currentUserId: authViewModel.currentUser?.id,
            isOwner: false
        )
    }

    var body: some View {
        NavigationStack {
            List {
                AccountHeaderSection(roleLabel: String(localized: "Co-caregiver"))

                if let family {
                    Section {
                        HStack {
                            Text("Family")
                            Spacer()
                            Text(family.name)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        let line = PlanSummary.line(for: family)
                        if line.needsAttention, let detail = line.detail {
                            Label(detail, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(SettingsStyle.warningText)
                        }
                    } footer: {
                        Text("You're told when a check-in is missed. The family's owner manages check-ins, invites and the plan.")
                    }
                }

                // Only when this Apple ID has a subscription: after handing the
                // family over, the ex-owner is a co-caregiver and this is the
                // only place in the app they can see or cancel it.
                if subscriptionService.currentTier != .free {
                    Section {
                        HStack {
                            Text("Your Apple ID")
                            Spacer()
                            Text(subscriptionService.currentTier.displayName)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        if storeRelation == .consistent {
                            Text("Your subscription pays for this family's plan.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if let message = PlanSummary.relationMessage(storeRelation) {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(SettingsStyle.warningText)
                        }
                        Button("Manage Subscription") { showManageSubscriptions = true }
                    } header: {
                        Text("Subscription")
                    }
                }

                Section {
                    NotificationStatusRow()
                } header: {
                    Text("Notifications")
                }

                AppLockSection()

                AccountDataSections(role: .viewer)

                AboutSection()

                Section {
                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tone: .neutral))
            .navigationTitle("Settings")
            .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    DailyOKHaptics.warning()
                    Task { await authViewModel.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(AccountCopy.signOutMessage(role: .viewer))
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .task { await loadFamily() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadFamily() } }
            }
        }
    }

    private func loadFamily() async {
        do {
            if let loaded = try await FamilyService.shared.getFamily() { family = loaded }
        } catch {
            // Keep what's shown; the rest of Settings doesn't depend on it.
        }
    }
}
