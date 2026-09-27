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

/// The people a co-caregiver works with, as Settings lists them: the owner
/// first, then the other active co-caregivers by name. Not the people being
/// checked on (they're on the dashboard), and not the reader.
enum ViewerCareTeam {
    struct Person: Identifiable, Equatable {
        let id: UUID
        let name: String
        let phone: String?
        let isOwner: Bool
    }

    static func people(members: [FamilyMember], ownerId: UUID, me: UUID?) -> [Person] {
        var seen = Set<UUID>()
        let people: [Person] = members.compactMap { member in
            guard member.status == .active, member.userId != me, !seen.contains(member.userId) else { return nil }
            let isOwner = member.userId == ownerId
            guard isOwner || member.role == .viewer else { return nil }
            seen.insert(member.userId)
            let name = member.user?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
            return Person(
                id: member.userId,
                name: name.isEmpty ? (isOwner ? String(localized: "Family owner") : String(localized: "Co-caregiver")) : name,
                phone: member.user?.phone,
                isOwner: isOwner
            )
        }
        return people.sorted { lhs, rhs in
            lhs.isOwner != rhs.isOwner
                ? lhs.isOwner
                : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// "Mom", "Mom and Dad", "Mom, Dad and Gran" — who a co-caregiver stops
    /// hearing about if they leave.
    static func receiverNames(members: [FamilyMember]) -> String? {
        let names = members
            .filter { $0.role == .receiver && $0.status == .active }
            .compactMap { $0.user?.displayName.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return ListFormatter.localizedString(byJoining: names)
    }

    /// The footer under the family: what a co-caregiver is told, and who runs
    /// the family. Help requests reach co-caregivers too (process-checkin-
    /// response pages every active co-caregiver), which the old "You're told
    /// when a check-in is missed" left out.
    static func roleFooter(ownerName: String?) -> String {
        let owner = ownerName.map { String(localized: "\($0), the family's owner,") } ?? String(localized: "The family's owner")
        return String(localized: "You're alerted if someone asks for help or misses a check-in. \(owner) manages check-ins, invites and the plan.")
    }
}

/// Settings for co-caregivers (viewers).
///
/// A co-caregiver — including the ex-owner after handing the family over —
/// can see the family, its plan and who pays for it, reach the owner and the
/// other co-caregivers, choose their own notifications (Live Activity, the
/// check-in summary, haptics), lock the app, manage their data, leave the
/// family, or delete their account.
struct ViewerSettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @StateObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(EscalationActivityManager.toggleKey) private var liveActivitiesEnabled = true
    @State private var showSignOutConfirmation = false
    @State private var showManageSubscriptions = false
    @State private var family: Family?
    @State private var members: [FamilyMember] = []
    @State private var familyLoadFailed = false
    @State private var isLoadingFamily = false
    @State private var showLeaveConfirm = false
    @State private var isLeaving = false
    @State private var leaveError: String?
    @State private var restoreResult: String?
    @State private var isRestoring = false

    private var myId: UUID? { authViewModel.currentUser?.id }

    private var owner: FamilyMember? {
        guard let family else { return nil }
        return members.first { $0.userId == family.ownerId }
    }

    private var ownerName: String? {
        guard let name = owner?.user?.displayName.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    private var careTeam: [ViewerCareTeam.Person] {
        guard let family else { return [] }
        return ViewerCareTeam.people(members: members, ownerId: family.ownerId, me: myId)
    }

    private var payerName: String? {
        guard let payer = family?.billingUserId, payer != myId else { return nil }
        guard let name = members.first(where: { $0.userId == payer })?.user?.displayName
            .trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    private var storeRelation: PlanSummary.StoreRelation {
        guard subscriptionService.hasLoadedEntitlements else { return .consistent }
        return PlanSummary.storeRelation(
            storeTier: subscriptionService.currentTier,
            family: family,
            currentUserId: myId,
            isOwner: false
        )
    }

    private var needsRestore: Bool {
        if case .notAppliedYet = storeRelation { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                AccountHeaderSection(roleLabel: String(localized: "Co-caregiver"))

                familySection

                if !careTeam.isEmpty {
                    careTeamSection
                }

                // Only when this Apple ID has a subscription: after handing the
                // family over, the ex-owner is a co-caregiver and this is the
                // only place in the app they can see or cancel it.
                if subscriptionService.currentTier != .free {
                    subscriptionSection
                }

                Section {
                    NotificationStatusRow()

                    // Co-caregivers get the escalation Live Activity too, and
                    // had no way to turn it off.
                    Toggle(isOn: $liveActivitiesEnabled) {
                        Label("Live Activity for Missed Check-ins", systemImage: "bell.and.waves.left.and.right")
                    }
                    .tint(DailyOKColor.green500)
                    .onChange(of: liveActivitiesEnabled) { _, enabled in
                        if !enabled { EscalationActivityManager.endAll() }
                    }

                    // A calm daily or weekly summary instead of only alarms
                    // (send-digest serves co-caregivers from 00062).
                    NavigationLink {
                        CaregiverDigestView()
                    } label: {
                        Label("Check-in Summary", systemImage: "text.bubble")
                    }
                } header: {
                    Text("Notifications")
                }

                AppLockSection()

                Section {
                    Toggle(isOn: $appState.hapticsEnabled) {
                        Label("Haptic Feedback", systemImage: "waveform.path")
                    }
                    .tint(DailyOKColor.green500)
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Subtle taps on navigation and buttons. Success and error notifications always fire.")
                }

                if family != nil {
                    leaveSection
                }

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
            .alert(String(localized: "Leave \(family?.name ?? String(localized: "this family"))?"),
                   isPresented: $showLeaveConfirm) {
                Button("Leave", role: .destructive) { Task { await leaveFamily() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(leaveMessage)
            }
            .alert("Restore Purchases", isPresented: Binding(
                get: { restoreResult != nil },
                set: { if !$0 { restoreResult = nil } }
            ), presenting: restoreResult) { _ in
                Button("OK", role: .cancel) { restoreResult = nil }
            } message: { message in
                Text(message)
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .task { await loadFamily() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadFamily() } }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var familySection: some View {
        if let family {
            Section {
                HStack {
                    Text("Family")
                    Spacer()
                    Text(family.name)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                let line = PlanSummary.viewerLine(
                    for: family,
                    payerName: payerName,
                    payerIsMe: family.billingUserId != nil && family.billingUserId == myId,
                    ownerName: ownerName
                )
                HStack {
                    Text("Plan")
                    Spacer()
                    Text(line.title)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                if let detail = line.detail {
                    Label {
                        Text(detail)
                    } icon: {
                        Image(systemName: line.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle")
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(line.needsAttention ? SettingsStyle.warningText : Color.secondary)
                }
            } footer: {
                Text(ViewerCareTeam.roleFooter(ownerName: ownerName))
            }
        } else if familyLoadFailed {
            Section {
                Label("Couldn't load your family.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SettingsStyle.warningText)
                Button {
                    Task { await loadFamily() }
                } label: {
                    HStack {
                        Text("Try Again")
                        Spacer()
                        if isLoadingFamily { ProgressView() }
                    }
                }
                .disabled(isLoadingFamily)
            } footer: {
                Text("Your alerts still arrive while this is showing.")
            }
        }
    }

    private var careTeamSection: some View {
        Section {
            ForEach(careTeam) { person in
                CareTeamRow(person: person)
            }
        } header: {
            Text("Care Team")
        } footer: {
            Text("Ask the owner to send a check-in, change a schedule or stop alerts.")
        }
    }

    private var subscriptionSection: some View {
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
            // The message above says "Tap Restore Purchases" for this case;
            // there used to be nothing to tap.
            if needsRestore {
                Button {
                    Task { await restore() }
                } label: {
                    HStack {
                        Text("Restore Purchases")
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                }
                .disabled(isRestoring || subscriptionService.isLoading)
                .accessibilityHint("Checks this Apple ID for a Daily OK subscription and applies it to your family")
            }
            Button("Manage Subscription") { showManageSubscriptions = true }
        } header: {
            Text("Subscription")
        }
    }

    private var leaveLabel: String {
        ownerName.map { String(localized: "Leave \($0)'s family") } ?? String(localized: "Leave this family")
    }

    private var leaveMessage: String {
        let about = ViewerCareTeam.receiverNames(members: members)
            .map { String(localized: "You'll stop getting alerts about \($0).") }
            ?? String(localized: "You'll stop getting this family's alerts.")
        let owner = ownerName ?? String(localized: "The family owner")
        return "\(about) \(String(localized: "\(owner) will see that you left. You can be invited again."))"
    }

    private var leaveSection: some View {
        Section {
            Button(role: .destructive) {
                showLeaveConfirm = true
            } label: {
                HStack {
                    Label(leaveLabel, systemImage: "person.crop.circle.badge.minus")
                    if isLeaving { Spacer(); ProgressView() }
                }
            }
            .disabled(isLeaving)
            if let leaveError {
                Text(leaveError)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
        } footer: {
            // Signing out only silences this phone; texts and other devices
            // keep coming until you leave.
            Text("Stops every alert about this family, including texts. Signing out only stops alerts on this iPhone. Your account stays.")
        }
    }

    // MARK: - Actions

    private func loadFamily() async {
        isLoadingFamily = true
        defer { isLoadingFamily = false }
        do {
            let fetched = try await FamilyService.shared.getFamily()
            if let loaded = fetched {
                family = loaded
                familyLoadFailed = false
                do {
                    members = try await FamilyService.shared.getFamilyMembers(familyId: loaded.id)
                } catch {
                    // Keep the last list: the care team and the payer's name
                    // are extras, not a reason to show the load error.
                }
            } else {
                // No active membership any more (removed, or the family was
                // closed): don't keep the old family and plan on screen.
                family = nil
                members = []
                familyLoadFailed = false
            }
        } catch {
            // Keep what's shown after a failed refresh; only an empty screen
            // needs the error row.
            if family == nil { familyLoadFailed = true }
        }
    }

    private func leaveFamily() async {
        guard let family, !isLeaving else { return }
        let owner = ownerName ?? String(localized: "the family owner")
        isLeaving = true
        leaveError = nil
        defer { isLeaving = false }
        do {
            try await FamilyService.shared.leaveFamily(familyId: family.id)
            // Nothing of this family's may stay on the Lock Screen: the owner
            // status widget and any escalation Live Activity.
            SharedOwnerPublisher.clear()
            EscalationActivityManager.endAll()
            DailyOKHaptics.success()
            // Re-resolve the role: with no membership left this routes to the
            // get-started choice.
            appState.roleRefreshRequest += 1
        } catch where FamilyService.isMissingFunction(error) {
            leaveError = String(localized: "Leaving from the app isn't available yet. Ask \(owner) to remove you from the family.")
        } catch {
            leaveError = OfflineCheckInService.isConnectivityError(error)
                ? String(localized: "Couldn't leave — you're offline. Try again when you're connected.")
                : String(localized: "Couldn't leave right now. Please try again, or ask \(owner) to remove you.")
        }
    }

    private func restore() async {
        isRestoring = true
        let outcome = await subscriptionService.restorePurchases()
        subscriptionService.errorMessage = nil
        isRestoring = false
        await loadFamily()
        restoreResult = outcome.message
        switch outcome {
        case .restored: DailyOKHaptics.success()
        case .failed: DailyOKHaptics.error()
        case .nothingToRestore: break
        }
    }
}

/// One person on the care team, with call and text when a number is on file.
private struct CareTeamRow: View {
    let person: ViewerCareTeam.Person

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                Text(person.isOwner ? "Owner" : "Co-caregiver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if let number = ContactQuickActions.dialableNumber(person.phone) {
                if let tel = URL(string: "tel:\(number)") {
                    Link(destination: tel) {
                        Image(systemName: "phone.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Call \(person.name)")
                }
                if let sms = URL(string: "sms:\(number)") {
                    Link(destination: sms) {
                        Image(systemName: "message.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Text \(person.name)")
                }
            }
        }
        .tint(DailyOKColor.green700)
    }
}
