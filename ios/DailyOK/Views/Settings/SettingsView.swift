import SwiftUI
import os
import AuthenticationServices
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @StateObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirmation = false
    @State private var deleteConfirmText = ""
    @State private var showSignOutConfirmation = false
    @State private var isExportingData = false
    @State private var exportedData: String?
    @State private var showExportSheet = false
    @AppStorage(EscalationActivityManager.toggleKey) private var liveActivitiesEnabled = true

    private var isOwner: Bool { appState.currentUserRole == .owner }

    var body: some View {
        NavigationStack {
            List {
                // Account
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
                    }
                }

                // Link Apple ID
                Section {
                    if authViewModel.hasLinkedApple {
                        Label("Apple ID Linked", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
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
                    }

                    if let message = authViewModel.linkAppleMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(
                                authViewModel.hasLinkedApple ? .green : .red
                            )
                    }
                } header: {
                    Text("Apple ID")
                } footer: {
                    if !authViewModel.hasLinkedApple {
                        Text("Link your Apple ID so you can use Sign in with Apple to access this account.")
                    }
                }

                // Subscription — owners only
                if isOwner {
                    Section("Subscription") {
                        HStack {
                            Text("Current Plan")
                            Spacer()
                            Text(subscriptionService.currentTier.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }

                        NavigationLink("Manage Subscription") {
                            SubscriptionView()
                        }

                        Button("Restore Purchases") {
                            Task { await subscriptionService.restorePurchases() }
                        }
                    }
                }

                // Notifications
                Section("Notifications") {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Label("Notification Settings", systemImage: "bell.badge")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }
                    .accessibilityHint("Opens iOS Settings to manage notifications for Daily OK")

                    if isOwner {
                        Toggle(isOn: $liveActivitiesEnabled) {
                            Label("Live Activity for Missed Check-ins", systemImage: "bell.and.waves.left.and.right")
                        }
                        .tint(DailyOKColor.green500)
                        .onChange(of: liveActivitiesEnabled) { _, enabled in
                            if !enabled { EscalationActivityManager.endAll() }
                        }

                        NavigationLink {
                            CaregiverDigestView()
                        } label: {
                            Label("Daily Summary", systemImage: "envelope.badge")
                        }
                    }
                }

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

                // Data & Privacy
                Section("Data & Privacy") {
                    Button {
                        Task { await exportUserData() }
                    } label: {
                        HStack {
                            Label("Export My Data", systemImage: "square.and.arrow.up")
                            Spacer()
                            if isExportingData {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isExportingData)

                    NavigationLink {
                        DataRetentionView()
                    } label: {
                        Label("Data Retention", systemImage: "clock.arrow.circlepath")
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link("Privacy Policy", destination: URL(string: "https://dailyok.net/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://dailyok.net/terms")!)
                }

                // Sign Out
                Section {
                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                }

                // Delete Account
                Section {
                    Button("Delete Account", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } footer: {
                    Text("Permanently deletes your account, family, and all associated data. This cannot be undone.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tone: .neutral))
            .navigationTitle("Settings")
            .alert("Sign Out", isPresented: $showSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    DailyOKHaptics.warning()
                    Task { await authViewModel.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out? You'll need to sign in again to access your family.")
            }
            .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                // Require the user to type DELETE so this irreversible action
                // can't be triggered by a single mistaken tap.
                TextField("Type DELETE to confirm", text: $deleteConfirmText)
                    .textInputAutocapitalization(.characters)
                Button("Delete Everything", role: .destructive) {
                    DailyOKHaptics.warning()
                    deleteConfirmText = ""
                    Task { await deleteAccount() }
                }
                .disabled(deleteConfirmText != "DELETE")
                Button("Cancel", role: .cancel) { deleteConfirmText = "" }
            } message: {
                Text("This will permanently delete your account, your family group, all check-in history, and remove all members. Type DELETE to confirm. This action cannot be undone.")
            }
            .task {
                await authViewModel.checkAppleLinkStatus()
            }
            .sheet(isPresented: $showExportSheet) {
                if let data = exportedData {
                    ShareLink(item: data) {
                        Label("Share Exported Data", systemImage: "square.and.arrow.up")
                    }
                    .presentationDetents([.medium])
                    .dailyokGlassSheet(style: .regular)
                }
            }
        }
    }

    @State private var settingsError: String?

    private func exportUserData() async {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            settingsError = DailyOKError.auth("Not signed in").localizedDescription
            return
        }
        isExportingData = true
        do {
            let response = try await SupabaseService.shared.client
                .rpc("export_user_data", params: ["p_user_id": session.user.id.uuidString])
                .execute()

            let jsonObject = try JSONSerialization.jsonObject(with: response.data)
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                exportedData = jsonString
                showExportSheet = true
            }
        } catch {
            settingsError = DailyOKError.network(error).localizedDescription
        }
        isExportingData = false
    }

    private func deleteAccount() async {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            settingsError = DailyOKError.auth("Not signed in").localizedDescription
            return
        }
        do {
            try await SupabaseService.shared.client
                .rpc("delete_user_account", params: ["p_user_id": session.user.id.uuidString])
                .execute()
            await authViewModel.signOut()
        } catch {
            settingsError = DailyOKError.network(error).localizedDescription
        }
    }
}

// MARK: - Data Retention Settings

struct DataRetentionView: View {
    @State private var retentionDays: Int = 365
    @State private var isLoading = true
    @State private var showSaved = false
    @State private var errorMessage: String?

    private let retentionOptions = [90, 180, 365, 730]

    var body: some View {
        List {
            Section {
                Picker("Keep check-in data for", selection: $retentionDays) {
                    Text("90 days").tag(90)
                    Text("6 months").tag(180)
                    Text("1 year").tag(365)
                    Text("2 years").tag(730)
                }
            } footer: {
                Text("Check-in records older than this will be automatically deleted. Default is 1 year.")
            }

            Section {
                Button("Save") {
                    Task { await saveRetention() }
                }
                .disabled(isLoading)
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
                    .background(.green, in: Capsule())
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true) // announced via UIAccessibility.post
            }
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
    }

    private func loadRetention() async {
        guard let family = try? await FamilyService.shared.getFamily() else {
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
        } catch {
            // Use default
        }
        isLoading = false
    }

    private func saveRetention() async {
        guard let family = try? await FamilyService.shared.getFamily() else { return }
        do {
            try await SupabaseService.shared.client
                .from("families")
                .update(["data_retention_days": retentionDays])
                .eq("id", value: family.id.uuidString)
                .execute()

            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: "Saved")
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
            errorMessage = DailyOKError.network(error).localizedDescription
            UIAccessibility.post(notification: .announcement, argument: "Couldn't save data retention")
        }
    }
}

struct SubscriptionView: View {
    @StateObject private var subscriptionService = SubscriptionService.shared
    @State private var showErrorAlert = false

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
            title: "Unlimited family members",
            description: "Add every parent, sibling, and caregiver — everyone stays in the loop."
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
            systemImage: "icloud.fill",
            title: "Long-term history",
            description: "Keep a full archive of check-ins for context and peace of mind."
        ),
        PaywallFeature(
            systemImage: "lock.shield.fill",
            title: "Privacy-first by design",
            description: "End-to-end encryption and rigorous data minimization — always."
        )
    ]

    private static let testimonial = Testimonial(
        quote: "Daily OK gives me peace of mind every morning. It's the first app I check.",
        author: "Sarah M., parent of two"
    )

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

                TestimonialCard(testimonial: Self.testimonial)
                    .padding(.horizontal, 16)

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
                        Text(subscriptionService.errorMessage ?? "Subscription options are unavailable right now.")
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
                    .tint(.green)
                    .disabled(subscriptionService.isLoading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(AmbientBackground(tone: .warm))
        .navigationTitle("Subscription")
        .task { await subscriptionService.loadProducts() }
        .alert("Subscription", isPresented: $showErrorAlert, presenting: subscriptionService.errorMessage) { _ in
            Button("OK", role: .cancel) { subscriptionService.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private func planRow(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(product.displayName)
                    .font(.headline)
                Spacer()
                if let pct = annualSavingsPercent(for: product) {
                    AnnualSavingsBadge(percentSaved: pct)
                }
                Text(product.displayPrice)
                    .fontWeight(.semibold)
            }

            Text(product.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if subscriptionService.purchasedProductIDs.contains(product.id) {
                Text("Current Plan")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            } else {
                Button("Subscribe") {
                    Task { await subscribe(product) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(subscriptionService.isLoading)
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
        do {
            _ = try await subscriptionService.purchase(product)
        } catch {
            subscriptionService.errorMessage = "Purchase couldn't be completed. Please try again."
            Log.subscription.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
        }
        // Surface any message the service set (failure, pending, sync-pending).
        if subscriptionService.errorMessage != nil {
            showErrorAlert = true
        }
    }

    private func restore() async {
        await subscriptionService.restorePurchases()
        if subscriptionService.errorMessage != nil {
            showErrorAlert = true
        }
    }
}
