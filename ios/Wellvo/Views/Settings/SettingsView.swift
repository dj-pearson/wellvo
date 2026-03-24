import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState
    @StateObject private var subscriptionService = SubscriptionService.shared
    @State private var showDeleteConfirmation = false
    @State private var isExportingData = false
    @State private var exportedData: String?
    @State private var showExportSheet = false

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

                    Link("Privacy Policy", destination: URL(string: "https://wellvo.net/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://wellvo.net/terms")!)
                }

                // Sign Out
                Section {
                    Button("Sign Out", role: .destructive) {
                        Task { await authViewModel.signOut() }
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
            .navigationTitle("Settings")
            .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account, your family group, all check-in history, and remove all members. This action cannot be undone.")
            }
            .sheet(isPresented: $showExportSheet) {
                if let data = exportedData {
                    ShareLink(item: data) {
                        Label("Share Exported Data", systemImage: "square.and.arrow.up")
                    }
                    .presentationDetents([.medium])
                }
            }
        }
    }

    @State private var settingsError: String?

    private func exportUserData() async {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            settingsError = WellvoError.auth("Not signed in").localizedDescription
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
            settingsError = WellvoError.network(error).localizedDescription
        }
        isExportingData = false
    }

    private func deleteAccount() async {
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            settingsError = WellvoError.auth("Not signed in").localizedDescription
            return
        }
        do {
            try await SupabaseService.shared.client
                .rpc("delete_user_account", params: ["p_user_id": session.user.id.uuidString])
                .execute()
            await authViewModel.signOut()
        } catch {
            settingsError = WellvoError.network(error).localizedDescription
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
            print("[Settings] Failed to save retention: \(error.localizedDescription)")
        }
    }
}

struct SubscriptionView: View {
    @StateObject private var subscriptionService = SubscriptionService.shared

    var body: some View {
        List {
            ForEach(subscriptionService.products, id: \.id) { product in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)
                        Spacer()
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
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Subscription")
        .task { await subscriptionService.loadProducts() }
    }
}
