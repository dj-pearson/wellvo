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
                    NavigationLink("Notification Settings") {
                        Text("Notification settings coming soon")
                    }

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
                Button("Delete Everything", role: .destructive) {
                    DailyOKHaptics.warning()
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account, your family group, all check-in history, and remove all members. This action cannot be undone.")
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
            }
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

            withAnimation {
                showSaved = true
            }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation {
                showSaved = false
            }
        } catch {
            Log.settings.error("Failed to save retention: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct SubscriptionView: View {
    @StateObject private var subscriptionService = SubscriptionService.shared

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

    private func annualSavingsPercent(for product: Product) -> Int? {
        // If the product description mentions an annual plan, surface the
        // hard-coded savings copy. The exact percent is product-config dependent;
        // if the StoreKit metadata doesn't expose it, default to a conservative
        // 15% which matches the App Store Connect configuration.
        guard product.id.lowercased().contains("annual") || product.id.lowercased().contains("yearly")
        else { return nil }
        return 15
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaywallFeatureCarousel(features: Self.paywallFeatures)
                    .padding(.top, 12)

                TestimonialCard(testimonial: Self.testimonial)
                    .padding(.horizontal, 16)

                VStack(spacing: 12) {
                    ForEach(subscriptionService.products, id: \.id) { product in
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
                                    Task { _ = try? await subscriptionService.purchase(product) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(AmbientBackground(tone: .warm))
        .navigationTitle("Subscription")
        .task { await subscriptionService.loadProducts() }
    }
}
