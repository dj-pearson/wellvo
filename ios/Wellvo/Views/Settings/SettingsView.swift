import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var subscriptionService = SubscriptionService.shared

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

                // Subscription
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

                // Notifications
                Section("Notifications") {
                    NavigationLink("Notification Settings") {
                        Text("Notification settings coming soon")
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
            }
            .navigationTitle("Settings")
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
