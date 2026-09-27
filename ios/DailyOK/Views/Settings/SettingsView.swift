import SwiftUI
import os
import AuthenticationServices
import StoreKit
import UserNotifications
import LocalAuthentication

/// Colors for Settings text that must stay readable (AA) on the grouped list
/// background: system green/orange text on white is ~2–3:1.
enum SettingsStyle {
    static let successText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.290, green: 0.871, blue: 0.502, alpha: 1) // green400
            : UIColor(red: 0.082, green: 0.502, blue: 0.239, alpha: 1) // green700
    })
    static let warningText = FamilyTabStyle.warningText
}

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @StateObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var showSignOutConfirmation = false
    @State private var showManageSubscriptions = false
    @AppStorage(EscalationActivityManager.toggleKey) private var liveActivitiesEnabled = true

    /// The family's plan as the server has it — what decides whether check-ins
    /// run. The StoreKit tier of this phone's Apple ID is shown only where it
    /// disagrees (PlanSummary.storeRelation).
    @State private var family: Family?
    @State private var familyLoadFailed = false
    @State private var activeCoCaregivers = 0
    @State private var restoreResult: String?
    @State private var isRestoring = false

    private var isOwner: Bool { appState.currentUserRole == .owner }

    /// Offered before an owner with co-caregivers deletes their account:
    /// handing the family over (Family tab) keeps everyone's check-ins going.
    private var transferInstead: (() -> Void)? {
        guard isOwner, activeCoCaregivers > 0 else { return nil }
        let appState = appState
        return { appState.selectedTab = .family }
    }

    var body: some View {
        NavigationStack {
            List {
                AccountHeaderSection()

                appleIDSection

                // Subscription — owners only (co-caregivers see their own
                // Apple ID's subscription, if any, in ViewerSettingsView).
                if isOwner {
                    subscriptionSection
                }

                // Notifications
                Section {
                    NotificationStatusRow()

                    if isOwner {
                        Toggle(isOn: $liveActivitiesEnabled) {
                            Label("Live Activity for Missed Check-ins", systemImage: "bell.and.waves.left.and.right")
                        }
                        .tint(DailyOKColor.green500)
                        .onChange(of: liveActivitiesEnabled) { _, enabled in
                            if !enabled { EscalationActivityManager.endAll() }
                        }

                        // The summary arrives as a push notification (daily or
                        // weekly), not an email.
                        NavigationLink {
                            CaregiverDigestView()
                        } label: {
                            Label("Check-in Summary", systemImage: "text.bubble")
                        }
                    }
                } header: {
                    Text("Notifications")
                }

                AppLockSection()

                Section("Devices") {
                    NavigationLink {
                        WatchSetupGuideView()
                    } label: {
                        Label("Set Up Apple Watch", systemImage: "applewatch")
                    }
                }

                // Feedback
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

                AccountDataSections(
                    role: appState.currentUserRole,
                    showsRetention: isOwner,
                    onTransferInstead: transferInstead
                )

                AboutSection()

                // Sign Out
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
                Text(AccountCopy.signOutMessage(role: appState.currentUserRole))
            }
            .alert("Restore Purchases", isPresented: Binding(
                get: { restoreResult != nil },
                set: { if !$0 { restoreResult = nil } }
            ), presenting: restoreResult) { _ in
                if subscriptionService.needsSupport {
                    Button("Contact Support") { openURL(SubscriptionService.supportURL) }
                }
                Button("OK", role: .cancel) { restoreResult = nil }
            } message: { message in
                Text(message)
            }
            .task {
                await authViewModel.checkAppleLinkStatus()
                await loadFamily()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadFamily() } }
            }
            .onDisappear { authViewModel.clearAppleLinkMessage() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        }
    }

    // MARK: - Apple ID

    @ViewBuilder
    private var appleIDSection: some View {
        Section {
            switch authViewModel.appleLinkState {
            case .linked:
                Label("Apple ID Linked", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(SettingsStyle.successText)
            case .notLinked:
                SignInWithAppleButton(.continue) { request in
                    authViewModel.configureAppleLinkRequest(request)
                } onCompletion: { result in
                    Task { await authViewModel.linkAppleID(result) }
                }
                .signInWithAppleButtonStyle(
                    colorScheme == .dark ? .white : .black
                )
                .frame(height: 44)
                .disabled(authViewModel.isLinkingApple)

                if authViewModel.isLinkingApple {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            case .unknown:
                // Not known yet (or the check failed offline). Showing the
                // link button here made already-linked users think they
                // weren't, and tapping it just produced an error.
                Button {
                    Task { await authViewModel.checkAppleLinkStatus() }
                } label: {
                    Label("Check Apple ID Link", systemImage: "arrow.clockwise")
                }
            }

            if let message = authViewModel.linkAppleMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(authViewModel.linkAppleMessageIsSuccess ? SettingsStyle.successText : Color.red)
            }
        } header: {
            Text("Apple ID")
        } footer: {
            if authViewModel.appleLinkState == .notLinked {
                Text("Link your Apple ID so you can use Sign in with Apple to access this account.")
            }
        }
    }

    // MARK: - Subscription

    private var storeRelation: PlanSummary.StoreRelation {
        guard subscriptionService.hasLoadedEntitlements else { return .consistent }
        return PlanSummary.storeRelation(
            storeTier: subscriptionService.currentTier,
            family: family,
            currentUserId: authViewModel.currentUser?.id,
            isOwner: isOwner
        )
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            if let family {
                let line = PlanSummary.line(for: family)
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

                if family.subscriptionTier != .free {
                    Text(PlanSummary.seatsLine(people: family.maxReceivers, coCaregivers: family.maxViewers))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if familyLoadFailed {
                Label("Couldn't load your plan.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SettingsStyle.warningText)
                Button("Try Again") { Task { await loadFamily() } }
            } else {
                HStack {
                    Text("Plan")
                    Spacer()
                    ProgressView()
                }
            }

            if let message = PlanSummary.relationMessage(storeRelation) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if subscriptionService.currentTier != .free {
                // Only the Apple ID that pays can manage the subscription, so
                // this follows StoreKit, not the family's plan.
                Button("Manage Subscription") {
                    showManageSubscriptions = true
                }
            } else {
                NavigationLink(storeRelation == .paidByAnotherMember ? "Take Over the Plan" : "View Plans") {
                    SubscriptionView()
                }
            }

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

            if let issue = subscriptionService.syncIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(SettingsStyle.warningText)
                if subscriptionService.needsSupport {
                    Link("Contact Support", destination: SubscriptionService.supportURL)
                }
            }
        } header: {
            Text("Subscription")
        }
    }

    private func loadFamily() async {
        do {
            if let loaded = try await FamilyService.shared.getFamily() {
                family = loaded
                familyLoadFailed = false
                SubscriptionService.shared.freeTierExpiresAt = loaded.freeTierExpiresAt
                if isOwner,
                   let members = try? await FamilyService.shared.getFamilyMembers(familyId: loaded.id) {
                    activeCoCaregivers = members.filter {
                        $0.role == .viewer && $0.status == .active && $0.userId != authViewModel.currentUser?.id
                    }.count
                }
            } else {
                family = nil
                familyLoadFailed = false
            }
        } catch {
            // Keep what's on screen after a failed refresh; only an empty
            // screen needs the error row.
            if family == nil { familyLoadFailed = true }
            Log.settings.error("Settings family load failed: \(error.localizedDescription, privacy: .public)")
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

// MARK: - Shared sections (owner, co-caregiver, receiver)

/// Name and sign-in identity. Shows the phone number for phone-only accounts
/// (the email line used to be an empty caption for them).
struct AccountHeaderSection: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.colorSchemeContrast) private var contrast
    var roleLabel: String? = nil

    var body: some View {
        Section("Account") {
            if let user = authViewModel.currentUser {
                HStack {
                    // Higher-contrast avatar: a solid fill with white initials
                    // under Increase Contrast, rather than green initials on a
                    // 20%-green wash (US-IOS106).
                    Circle()
                        .fill(contrast == .increased ? DailyOKColor.green700 : Color.green.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Text(String(user.displayName.prefix(1)).uppercased())
                                .fontWeight(.bold)
                                .foregroundStyle(contrast == .increased ? Color.white : SettingsStyle.successText)
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.body)
                        if let identity = user.email ?? user.phone, !identity.isEmpty {
                            Text(identity)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if let roleLabel {
                    HStack {
                        Text("Role")
                        Spacer()
                        Text(roleLabel)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct AboutSection: View {
    var body: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Link("Privacy Policy", destination: URL(string: "https://dailyok.net/privacy")!)
            Link("Terms of Service", destination: URL(string: "https://dailyok.net/terms")!)
            Link("Help & Support", destination: SubscriptionService.supportURL)
        }
    }
}

/// Whether notifications can actually reach this phone. Escalation alerts are
/// the product; the Settings row used to be a bare link to iOS Settings that
/// never said notifications were off, and the dashboard banner can be
/// dismissed for a week.
struct NotificationStatusRow: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?
    @State private var timeSensitiveOff = false

    var body: some View {
        Button {
            Task { await openOrAsk() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Notifications", systemImage: "bell.badge")
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(isProblem ? SettingsStyle.warningText : Color.secondary)
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .accessibilityHidden(true)
                }
                if let warning {
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(SettingsStyle.warningText)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(status == .notDetermined ? "Asks to allow notifications" : "Opens iOS Settings to manage notifications for Daily OK")
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private var statusText: String {
        guard let status else { return "" }
        switch status {
        case .authorized, .provisional, .ephemeral:
            return timeSensitiveOff ? String(localized: "On · Time Sensitive off") : String(localized: "On")
        case .denied: return String(localized: "Off")
        case .notDetermined: return String(localized: "Not set up")
        @unknown default: return ""
        }
    }

    private var isProblem: Bool {
        status == .denied || status == .notDetermined || timeSensitiveOff
    }

    private var warning: String? {
        if status == .denied || status == .notDetermined {
            return String(localized: "You won't be alerted on this iPhone when a check-in is missed.")
        }
        return timeSensitiveOff
            ? String(localized: "Missed check-in alerts may be held back by Focus. Turn on Time Sensitive Notifications for Daily OK.")
            : nil
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
        timeSensitiveOff = settings.authorizationStatus == .authorized && settings.timeSensitiveSetting == .disabled
    }

    private func openOrAsk() async {
        if status == .notDetermined {
            _ = try? await PushNotificationService.shared.requestPermission()
            await refresh()
            return
        }
        if let url = URL(string: UIApplication.openSettingsURLString) {
            _ = await UIApplication.shared.open(url)
        }
    }
}

/// "Require Face ID". The lock existed (BiometricService, the lock screen,
/// token withholding) but nothing in the app could turn it on or off: the
/// post-sign-in prompt that was meant to offer it is never presented.
struct AppLockSection: View {
    /// Read synchronously (LAContext is cheap) so the section doesn't depend on
    /// a `.task` attached to content that may not exist yet.
    private let biometry: LABiometryType = {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }()
    @State private var isOn = BiometricService.isEnabledPreference
    @State private var isChanging = false

    private var available: Bool { biometry == .faceID || biometry == .touchID || biometry == .opticID }
    private var name: String {
        switch biometry {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }

    var body: some View {
        if available {
            Section {
                    Toggle(isOn: Binding(
                        get: { isOn },
                        set: { newValue in Task { await change(to: newValue) } }
                    )) {
                        Label(String(localized: "Require \(name)"), systemImage: name == "Touch ID" ? "touchid" : "faceid")
                    }
                    .tint(DailyOKColor.green500)
                    .disabled(isChanging)
                    .onAppear { isOn = BiometricService.isEnabledPreference }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Asks for \(name) or your passcode when you open Daily OK. Alerts still arrive while the app is locked.")
                }
        }
    }

    private func change(to newValue: Bool) async {
        guard newValue != isOn, !isChanging else { return }
        isChanging = true
        defer { isChanging = false }
        // Turning the lock OFF is as sensitive as the data behind it, so it
        // needs the owner's face or passcode. Turning it on protects more and
        // needs nothing (a prompt here would also be followed by the resume
        // lock as the app becomes active again).
        if !newValue {
            let reason = String(localized: "Turn off \(name) for Daily OK")
            guard await BiometricService.shared.authenticate(reason: reason) else { return }
        }
        await BiometricService.shared.setEnabled(newValue)
        if newValue { await BiometricService.shared.setSkipped(false) }
        // Changed from inside the unlocked app: this session has shown
        // presence, so the widget / Siri / watch keep their tokens until the
        // next background. The Lock Screen "I'm OK" / snooze actions follow
        // the setting (authentication required while it is on).
        SharedTokenGate.markUnlocked()
        NotificationCategories.register()
        isOn = newValue
        DailyOKHaptics.success()
    }
}

/// A file to share, for `.sheet(item:)`.
private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Export My Data and Delete Account, for every role.
///
/// Both used to exist only in the owner's Settings: co-caregivers (including an
/// ex-owner after a transfer) and receivers had no way to delete their account
/// or get their data (App Store guideline 5.1.1(v); GDPR Art. 15/17/20). The
/// RPCs were already self-scoped (auth.uid() = p_user_id), so this is UI only.
struct AccountDataSections: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var subscriptionService = SubscriptionService.shared

    let role: UserRole?
    var showsRetention: Bool = false
    /// For an owner with co-caregivers: offered before deleting, since handing
    /// the family over keeps everyone's check-ins running.
    var onTransferInstead: (() -> Void)? = nil

    @State private var isExporting = false
    @State private var exportFile: ExportFile?
    @State private var showDeleteIntro = false
    @State private var showDeleteConfirm = false
    @State private var deleteConfirmText = ""
    @State private var isDeleting = false
    @State private var pendingError: String?
    @State private var errorMessage: String?
    @State private var showManageSubscriptions = false

    private var hasStoreSubscription: Bool { subscriptionService.currentTier != .free }

    var body: some View {
        Section {
            Button {
                Task { await exportUserData() }
            } label: {
                HStack {
                    Label("Export My Data", systemImage: "square.and.arrow.up")
                    Spacer()
                    if isExporting {
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)
            .accessibilityHint("Creates a file with everything Daily OK stores about you")
            .sheet(item: $exportFile) { file in
                ShareSheet(activityItems: [file.url])
            }

            if showsRetention {
                NavigationLink {
                    DataRetentionView()
                } label: {
                    Label("Data Retention", systemImage: "clock.arrow.circlepath")
                }
            }
        } header: {
            Text("Data & Privacy")
        } footer: {
            if role == .receiver {
                Text("A file with everything Daily OK stores about you.")
            } else {
                Text("A file with everything Daily OK stores about you. For a readable record of someone's check-ins, create a report in the History tab.")
            }
        }

        Section {
            Button("Delete Account", role: .destructive) {
                deleteConfirmText = ""
                showDeleteIntro = true
            }
            .disabled(isDeleting)
            .alert("Delete Your Account?", isPresented: $showDeleteIntro) {
                if let onTransferInstead {
                    Button("Make a Co-Caregiver the Owner") { onTransferInstead() }
                }
                if hasStoreSubscription {
                    Button("Manage Subscription") { showManageSubscriptions = true }
                }
                Button("Continue", role: .destructive) { showDeleteConfirm = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(AccountCopy.deleteMessage(role: role, hasStoreSubscription: hasStoreSubscription)
                    + (onTransferInstead != nil
                        ? " " + String(localized: "To keep check-ins running, make a co-caregiver the owner first.")
                        : ""))
            }
            .alert("Delete Account", isPresented: $showDeleteConfirm) {
                // Typing DELETE keeps a single mistaken tap from destroying
                // years of a family's history.
                TextField("Type DELETE to confirm", text: $deleteConfirmText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Delete Everything", role: .destructive) {
                    DailyOKHaptics.warning()
                    deleteConfirmText = ""
                    Task { await deleteAccount() }
                }
                .disabled(deleteConfirmText.trimmingCharacters(in: .whitespaces).uppercased() != "DELETE")
                Button("Cancel", role: .cancel) { deleteConfirmText = "" }
            } message: {
                Text("This can't be undone. Type DELETE to confirm.")
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ), presenting: errorMessage) { _ in
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .fullScreenCover(isPresented: $isDeleting, onDismiss: {
                if let pendingError {
                    errorMessage = pendingError
                    self.pendingError = nil
                }
            }) {
                DeletingAccountView()
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        } footer: {
            if role == .owner {
                Text("Permanently deletes your account, your family and all of its check-in history. This can't be undone.")
            } else {
                Text("Permanently deletes your account and removes you from the family. This can't be undone.")
            }
        }
    }

    private func exportUserData() async {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            errorMessage = String(localized: "You're signed out. Sign in again to export your data.")
            return
        }
        isExporting = true
        defer { isExporting = false }
        do {
            let response = try await SupabaseService.shared.client
                .rpc("export_user_data", params: ["p_user_id": session.user.id.uuidString])
                .execute()

            let jsonObject = try JSONSerialization.jsonObject(with: response.data)
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            // A dated .json file, not a multi-megabyte string pasted into
            // whatever the share sheet picks.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(PlanSummary.exportFileName())
            try jsonData.write(to: url, options: [.atomic, .completeFileProtection])
            exportFile = ExportFile(url: url)
        } catch {
            Log.settings.error("Export failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AccountCopy.failureMessage(for: error, action: String(localized: "export your data"))
        }
    }

    private func deleteAccount() async {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            errorMessage = String(localized: "You're signed out. Sign in again to delete your account.")
            return
        }
        let userId = session.user.id
        // Let the confirmation alert finish dismissing before the progress
        // cover is presented (two presentations at once can drop the second).
        try? await Task.sleep(for: .milliseconds(350))
        isDeleting = true
        do {
            try await SupabaseService.shared.client
                .rpc("delete_user_account", params: ["p_user_id": userId.uuidString])
                .execute()
            isDeleting = false
            await authViewModel.signOut()
        } catch {
            // The server may have finished and only the reply was lost. If the
            // account is gone, finish signing out instead of showing an error
            // to someone signed in as a deleted user.
            if await Self.accountIsGone(userId) {
                isDeleting = false
                await authViewModel.signOut()
                return
            }
            Log.settings.error("Delete account failed: \(error.localizedDescription, privacy: .public)")
            pendingError = AccountCopy.failureMessage(for: error, action: String(localized: "delete your account"))
            isDeleting = false
        }
    }

    private static func accountIsGone(_ userId: UUID) async -> Bool {
        struct Row: Decodable { let id: UUID }
        guard let rows: [Row] = try? await SupabaseService.shared.client
            .from("users")
            .select("id")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        else { return false }
        return rows.isEmpty
    }
}

/// Shown while the account is being deleted, so nothing can be tapped halfway.
private struct DeletingAccountView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Deleting your account…")
                .font(.headline)
            Text("This takes a few seconds. Please keep the app open.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
        .accessibilityElement(children: .combine)
    }
}

/// The family a receiver can leave from Account & Privacy.
struct ReceiverLeaveContext: Equatable {
    let familyId: UUID
    let familyName: String?
    let ownerName: String?
}

/// Account and privacy for people who are checked on. Their home screen has
/// only a menu, so this opens as a sheet from it.
struct ReceiverAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    /// nil hides "Leave family" (family not loaded yet).
    var leave: ReceiverLeaveContext? = nil
    @State private var showLeaveConfirm = false
    @State private var isLeaving = false
    @State private var leaveError: String?

    private var ownerLabel: String { leave?.ownerName ?? String(localized: "your family") }

    var body: some View {
        NavigationStack {
            List {
                AccountHeaderSection()
                if let leave {
                    Section {
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            HStack {
                                Label(leave.ownerName.map { String(localized: "Leave \($0)'s family") }
                                      ?? String(localized: "Leave this family"),
                                      systemImage: "person.crop.circle.badge.minus")
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
                        Text("Stops your daily check-ins with this family. \(ownerLabel.capitalizedFirstLetter) will be told you left. Your account stays; you can be invited again.")
                    }
                }
                AccountDataSections(role: .receiver)
                AboutSection()
            }
            .navigationTitle("Account & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(String(localized: "Leave \(leave?.familyName ?? String(localized: "this family"))?"),
                   isPresented: $showLeaveConfirm) {
                Button("Leave", role: .destructive) { Task { await leaveFamily() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll stop getting check-in reminders, and \(ownerLabel) will no longer be alerted about your check-ins. \(ownerLabel.capitalizedFirstLetter) will see that you left.")
            }
        }
    }

    private func leaveFamily() async {
        guard let leave, !isLeaving else { return }
        isLeaving = true
        leaveError = nil
        defer { isLeaving = false }
        do {
            try await FamilyService.shared.leaveFamily(familyId: leave.familyId)
            // Nothing to check in to any more: the widget, Siri and the watch
            // must not keep offering "I'm OK" for this family.
            SharedCheckInPublisher.clear()
            await PushNotificationService.shared.cancelLocalCheckinFallback()
            DailyOKHaptics.success()
            dismiss()
            // Re-resolve the role: with no membership left this routes to the
            // get-started choice.
            appState.roleRefreshRequest += 1
        } catch where FamilyService.isMissingFunction(error) {
            leaveError = String(localized: "Leaving from the app isn't available yet. Ask \(ownerLabel) to remove you from the family.")
        } catch {
            leaveError = OfflineCheckInService.isConnectivityError(error)
                ? String(localized: "Couldn't leave — you're offline. Try again when you're connected.")
                : String(localized: "Couldn't leave right now. Please try again, or ask \(ownerLabel) to remove you.")
        }
    }
}

private extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Data Retention Settings

struct DataRetentionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var retentionDays: Int = 365
    /// The value on the server. Save is only offered when the choice differs,
    /// and a shorter window is confirmed first.
    @State private var loadedDays: Int?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSaved = false
    @State private var showShortenConfirm = false
    @State private var errorMessage: String?
    /// True when the current value couldn't be read. We must NOT let the user
    /// Save in this state — saving would clobber the real server value with the
    /// 365 default (US-IOS094).
    @State private var loadFailed = false

    private var isDirty: Bool { loadedDays != nil && retentionDays != loadedDays }

    var body: some View {
        List {
            Section {
                Picker("Keep check-in history for", selection: $retentionDays) {
                    Text("90 days").tag(90)
                    Text("6 months").tag(180)
                    Text("1 year").tag(365)
                    Text("2 years").tag(730)
                }
            } footer: {
                Text("Applies to everyone in your family. Check-ins older than this are deleted automatically each night, and can't be recovered. Default is 1 year.")
            }

            if loadFailed {
                Section {
                    Label("Couldn't load your current setting.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SettingsStyle.warningText)
                    Button("Retry") {
                        Task { await loadRetention() }
                    }
                }
            }

            Section {
                Button {
                    if PlanSummary.retentionShortens(from: loadedDays, to: retentionDays) {
                        showShortenConfirm = true
                    } else {
                        Task { await saveRetention() }
                    }
                } label: {
                    HStack {
                        Text("Save")
                        Spacer()
                        if isSaving { ProgressView() }
                    }
                }
                // Block Save while loading or after a failed load so we don't
                // overwrite the real server value with the default (US-IOS094).
                .disabled(isLoading || loadFailed || isSaving || !isDirty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(tone: .neutral))
        .navigationTitle("Data Retention")
        .overlay {
            if showSaved {
                Text("Saved")
                    .font(.headline)
                    .padding()
                    .background(DailyOKColor.green700, in: Capsule())
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true) // announced via UIAccessibility.post
            }
        }
        .confirmationDialog(
            "Delete older check-ins?",
            isPresented: $showShortenConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Older Check-ins", role: .destructive) {
                Task { await saveRetention() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let cutoff = PlanSummary.retentionCutoff(days: retentionDays)
            Text("Check-ins from before \(cutoff.formatted(date: .abbreviated, time: .omitted)) will be permanently deleted tonight, for everyone in your family. To keep a copy, create a report in the History tab first.")
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await loadRetention() }
        // Reload on foreground so a value changed elsewhere isn't re-saved stale
        // (US-IOS111) — but never over a choice the user hasn't saved yet.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, !isDirty { Task { await loadRetention() } }
        }
    }

    private func loadRetention() async {
        isLoading = true
        loadFailed = false
        guard let family = try? await FamilyService.shared.getFamily() else {
            loadFailed = true
            isLoading = false
            return
        }
        // Read current retention from family record
        do {
            struct FamilyRetention: Codable {
                let dataRetentionDays: Int
                enum CodingKeys: String, CodingKey {
                    case dataRetentionDays = "data_retention_days"
                }
            }
            let result: FamilyRetention = try await SupabaseService.shared.client
                .from("families")
                .select("data_retention_days")
                .eq("id", value: family.id.uuidString)
                .single()
                .execute()
                .value
            retentionDays = result.dataRetentionDays
            loadedDays = result.dataRetentionDays
        } catch {
            // Don't silently fall back to the default and then let Save clobber
            // the real server value — flag the failure and block Save.
            loadFailed = true
        }
        isLoading = false
    }

    private func saveRetention() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        guard let family = try? await FamilyService.shared.getFamily() else {
            // Used to return silently, so Save looked dead offline.
            DailyOKHaptics.error()
            errorMessage = String(localized: "Couldn't reach your family's settings. Check your connection and try again.")
            return
        }
        do {
            try await SupabaseService.shared.client
                .from("families")
                .update(["data_retention_days": retentionDays])
                .eq("id", value: family.id.uuidString)
                .execute()

            loadedDays = retentionDays
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Saved"))
            withAnimation {
                showSaved = true
            }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation {
                showSaved = false
            }
        } catch {
            Log.settings.error("Failed to save retention: \(error.localizedDescription, privacy: .public)")
            DailyOKHaptics.error()
            errorMessage = AccountCopy.failureMessage(for: error, action: String(localized: "save this setting"))
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Couldn't save data retention"))
        }
    }
}

// MARK: - Plans (paywall)

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var subscriptionService = SubscriptionService.shared
    @State private var showErrorAlert = false
    @State private var purchasedTier: SubscriptionTier?
    @State private var restoreMessage: String?

    /// Subscription plans only — exclude add-on SKUs, which aren't standalone
    /// plans and shouldn't render as "Subscribe" rows in the main paywall list.
    private var planProducts: [Product] {
        subscriptionService.products.filter {
            $0.id != SubscriptionService.ProductIDs.addonReceiver &&
            $0.id != SubscriptionService.ProductIDs.addonViewer
        }
    }

    private static let paywallFeatures: [PaywallFeature] = [
        PaywallFeature(
            systemImage: "person.2.fill",
            // Plans are capped (1 / 3 / 6 people to check on, 3 / 5 / 10
            // co-caregivers), so "unlimited" was not true.
            title: "Room for the whole family",
            description: "Check on up to 6 people and add up to 10 co-caregivers, depending on your plan."
        ),
        PaywallFeature(
            systemImage: "bell.badge.fill",
            title: "Smart escalation alerts",
            description: "If a check-in is missed, the right person hears about it right away."
        ),
        PaywallFeature(
            systemImage: "chart.line.uptrend.xyaxis",
            title: "Pattern insights",
            description: "Spot mood and timing trends across the family at a glance."
        ),
        PaywallFeature(
            systemImage: "clock.arrow.circlepath",
            // Retention is 1 year by default and 2 at most (Data Retention),
            // so "a full archive" was not true.
            title: "Up to 2 years of history",
            description: "Look back over check-ins, and create a report to share with a doctor or family."
        ),
        PaywallFeature(
            systemImage: "lock.shield.fill",
            title: "Privacy-first by design",
            description: "Encrypted connections and strict data minimization — your family's data is never sold."
        )
    ]
    // The hard-coded "Sarah M." testimonial was removed: nothing showed it was
    // a real, consented customer quote (App Store 2.3 / FTC endorsement rules).

    /// Real annual savings vs. paying monthly for the same tier, computed from
    /// StoreKit prices (never hardcoded — App Store guideline 3.1). Returns nil
    /// for monthly products or when the matching monthly SKU hasn't loaded.
    private func annualSavingsPercent(for product: Product) -> Int? {
        let monthlyID: String?
        switch product.id {
        case SubscriptionService.ProductIDs.caregiverYearly: monthlyID = SubscriptionService.ProductIDs.caregiverMonthly
        case SubscriptionService.ProductIDs.familyYearly: monthlyID = SubscriptionService.ProductIDs.familyMonthly
        case SubscriptionService.ProductIDs.familyPlusYearly: monthlyID = SubscriptionService.ProductIDs.familyPlusMonthly
        default: return nil
        }
        guard let monthlyID,
              let monthly = subscriptionService.products.first(where: { $0.id == monthlyID })
        else { return nil }
        let annualIfMonthly = monthly.price * Decimal(12)
        guard annualIfMonthly > 0 else { return nil }
        let saved = (annualIfMonthly - product.price) / annualIfMonthly
        let pct = NSDecimalNumber(decimal: saved * Decimal(100)).intValue
        return pct > 0 ? pct : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaywallFeatureCarousel(features: Self.paywallFeatures)
                    .padding(.top, 12)

                if subscriptionService.isLoading && planProducts.isEmpty {
                    ProgressView("Loading plans…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if planProducts.isEmpty {
                    // Load failed or no plans available — give the user a way out
                    // instead of a blank paywall.
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        // Load-failed state only — keep this distinct from the
                        // purchase-failed alert so the same error isn't shown
                        // twice (US-IOS096).
                        Text("Subscription options are unavailable right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await subscriptionService.loadProducts() }
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                } else {
                    VStack(spacing: 12) {
                        ForEach(planProducts, id: \.id) { product in
                            planRow(product)
                        }
                    }
                    .padding(.horizontal, 16)

                    Button {
                        Task { await restore() }
                    } label: {
                        Text("Restore Purchases")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(DailyOKColor.green700)
                    .disabled(subscriptionService.isLoading)
                    .padding(.horizontal, 16)

                    disclosure
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(AmbientBackground(tone: .warm))
        .navigationTitle("Subscription")
        .task { await subscriptionService.loadProducts() }
        .alert("Subscription", isPresented: $showErrorAlert, presenting: subscriptionService.errorMessage) { _ in
            if subscriptionService.needsSupport {
                Button("Contact Support") { openURL(SubscriptionService.supportURL) }
            }
            Button("OK", role: .cancel) { subscriptionService.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert("You're on \(purchasedTier?.displayName ?? "")", isPresented: Binding(
            get: { purchasedTier != nil },
            set: { if !$0 { purchasedTier = nil } }
        ), presenting: purchasedTier) { _ in
            Button("Done") {
                purchasedTier = nil
                dismiss()
            }
        } message: { tier in
            if let seats = PlanSummary.seats(for: tier) {
                Text("Thank you. You can now check on up to \(seats.people) \(seats.people == 1 ? "person" : "people") and add up to \(seats.coCaregivers) co-caregivers.")
            } else {
                Text("Thank you for subscribing.")
            }
        }
        .alert("Restore Purchases", isPresented: Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        ), presenting: restoreMessage) { _ in
            if subscriptionService.needsSupport {
                Button("Contact Support") { openURL(SubscriptionService.supportURL) }
            }
            Button("OK", role: .cancel) { restoreMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    /// Auto-renewal terms and legal links, required on the purchase screen
    /// (App Store guideline 3.1.2).
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscriptions renew automatically at the price shown for each period until cancelled. Payment is charged to your Apple ID. Cancel at least 24 hours before the period ends in Settings › Apple ID › Subscriptions to avoid being charged for the next one.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://dailyok.net/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://dailyok.net/privacy")!)
            }
            .font(.caption.weight(.medium))
            .tint(DailyOKColor.green700)
        }
    }

    private func priceText(_ product: Product) -> String {
        SubscriptionService.priceWithPeriod(
            displayPrice: product.displayPrice,
            periodUnit: product.subscription?.subscriptionPeriod.unit
        )
    }

    @ViewBuilder
    private func planRow(_ product: Product) -> some View {
        let price = priceText(product)
        let tier = subscriptionService.tier(forProductID: product.id)
        let seats = tier.flatMap { PlanSummary.seats(for: $0) }
        let savings = annualSavingsPercent(for: product)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(product.displayName)
                    .font(.headline)
                Spacer()
                if let savings {
                    AnnualSavingsBadge(percentSaved: savings)
                }
                // With the period ("$3.99/mo", "$29.99/yr"): a bare price
                // couldn't be told apart from a yearly one.
                Text(price)
                    .fontWeight(.semibold)
            }
            .accessibilityElement(children: .combine)

            if let seats {
                Text(PlanSummary.seatsLine(people: seats.people, coCaregivers: seats.coCaregivers))
                    .font(.subheadline)
            }

            if !product.description.isEmpty {
                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Frame every row relative to the active tier so a subscriber sees
            // "Current Plan" / "Upgrade" / "Switch" instead of an undifferentiated
            // "Subscribe" on every tier (US-IOS096).
            let savingsText = savings.map { ", " + String(localized: "save \($0)%") } ?? ""
            switch subscriptionService.relation(forProductID: product.id) {
            case .current:
                Text("Current Plan")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(SettingsStyle.successText)
            case .upgrade:
                Button("Upgrade") { Task { await subscribe(product) } }
                    .buttonStyle(.borderedProminent)
                    .tint(DailyOKColor.green700)
                    .disabled(subscriptionService.isLoading)
                    .accessibilityLabel("Upgrade to \(product.displayName), \(price)\(savingsText)")
            case .switchPlan:
                Button("Switch to this plan") { Task { await subscribe(product) } }
                    .buttonStyle(.bordered)
                    .tint(DailyOKColor.green700)
                    .disabled(subscriptionService.isLoading)
                    .accessibilityLabel("Switch to \(product.displayName), \(price)\(savingsText)")
            case .none:
                Button("Subscribe") { Task { await subscribe(product) } }
                    .buttonStyle(.borderedProminent)
                    .tint(DailyOKColor.green700)
                    .disabled(subscriptionService.isLoading)
                    .accessibilityLabel("Subscribe to \(product.displayName), \(price)\(savingsText)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func subscribe(_ product: Product) async {
        var transaction: StoreKit.Transaction?
        do {
            transaction = try await subscriptionService.purchase(product)
        } catch {
            subscriptionService.errorMessage = String(localized: "Purchase couldn't be completed. Please try again.")
            Log.subscription.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
        }
        // Surface any message the service set (failure, pending, sync-pending).
        if subscriptionService.errorMessage != nil {
            showErrorAlert = true
        } else if transaction != nil, let tier = subscriptionService.tier(forProductID: product.id) {
            // A purchase used to end with no confirmation at all.
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "You're on \(tier.displayName)"))
            purchasedTier = tier
        }
    }

    private func restore() async {
        let outcome = await subscriptionService.restorePurchases()
        subscriptionService.errorMessage = nil
        restoreMessage = outcome.message
    }
}
