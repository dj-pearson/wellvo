import Foundation
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var currentTier: SubscriptionTier = .free
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Product IDs (update these to match your App Store Connect configuration)

    struct ProductIDs {
        static let familyMonthly = "net.wellvo.family.monthly"
        static let familyYearly = "net.wellvo.family.yearly"
        static let familyPlusMonthly = "net.wellvo.familyplus.monthly"
        static let familyPlusYearly = "net.wellvo.familyplus.yearly"
        static let addonReceiver = "net.wellvo.addon.receiver"
        static let addonViewer = "net.wellvo.addon.viewer"

        static let all: Set<String> = [
            familyMonthly, familyYearly,
            familyPlusMonthly, familyPlusYearly,
            addonReceiver, addonViewer,
        ]

        static let familyPlus: Set<String> = [familyPlusMonthly, familyPlusYearly]
        static let family: Set<String> = [familyMonthly, familyYearly]
    }

    private var updateTask: Task<Void, Never>?

    init() {
        updateTask = Task {
            await listenForTransactions()
        }
        Task {
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        do {
            products = try await Product.products(for: ProductIDs.all)
                .sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Failed to load subscription options."
            print("Failed to load products: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Link transaction to the Supabase user for server-side reconciliation
        let appAccountToken = await currentUserUUID()

        var purchaseOptions: Set<Product.PurchaseOption> = []
        if let token = appAccountToken {
            purchaseOptions.insert(.appAccountToken(token))
        }

        let result = try await product.purchase(options: purchaseOptions)

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()

            // Sync to backend with retry
            await syncSubscriptionToBackend(transaction)

            return transaction

        case .userCancelled:
            return nil

        case .pending:
            errorMessage = "Purchase is pending approval."
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - Entitlement Check

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                // Only include non-expired subscriptions
                if let expirationDate = transaction.expirationDate {
                    if expirationDate > Date() {
                        purchased.insert(transaction.productID)
                    }
                } else {
                    // Non-subscription purchases (add-ons without expiry)
                    purchased.insert(transaction.productID)
                }
            }
        }

        purchasedProductIDs = purchased
        updateCurrentTier()
    }

    func restorePurchases() async {
        isLoading = true
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "Failed to restore purchases."
        }
        await updatePurchasedProducts()
        isLoading = false
    }

    /// Check if the user has access to a specific feature tier
    func hasAccess(to tier: SubscriptionTier) -> Bool {
        switch tier {
        case .free: return true
        case .family: return currentTier == .family || currentTier == .familyPlus
        case .familyPlus: return currentTier == .familyPlus
        }
    }

    // MARK: - Private

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result) {
                await updatePurchasedProducts()
                await transaction.finish()
                await syncSubscriptionToBackend(transaction)
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw SubscriptionError.verificationFailed(error)
        case .verified(let item):
            return item
        }
    }

    /// Determine the current tier using exact product ID matching (not substring)
    private func updateCurrentTier() {
        // Check Family+ first (higher tier takes precedence)
        if !purchasedProductIDs.isDisjoint(with: ProductIDs.familyPlus) {
            currentTier = .familyPlus
        } else if !purchasedProductIDs.isDisjoint(with: ProductIDs.family) {
            currentTier = .family
        } else {
            currentTier = .free
        }
    }

    /// Sync subscription status to the Supabase backend with exponential backoff retry
    private func syncSubscriptionToBackend(_ transaction: StoreKit.Transaction, attempt: Int = 1) async {
        let maxRetries = 3
        do {
            try await SupabaseService.shared.client.functions.invoke(
                "subscription-webhook",
                options: .init(body: [
                    "product_id": transaction.productID,
                    "transaction_id": String(transaction.id),
                    "original_id": String(transaction.originalID),
                    "expiration_date": transaction.expirationDate?.ISO8601Format() ?? "",
                    "app_account_token": transaction.appAccountToken?.uuidString ?? "",
                ])
            )
        } catch {
            if attempt < maxRetries {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000 // exponential backoff
                try? await Task.sleep(nanoseconds: delay)
                await syncSubscriptionToBackend(transaction, attempt: attempt + 1)
            } else {
                print("Failed to sync subscription after \(maxRetries) attempts: \(error.localizedDescription)")
                errorMessage = "Subscription activated but sync pending. It will retry automatically."
            }
        }
    }

    /// Get the current Supabase user's UUID to link with the StoreKit transaction
    private func currentUserUUID() async -> UUID? {
        guard let session = try? await SupabaseService.shared.client.auth.session else { return nil }
        return session.user.id
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case verificationFailed(Error)
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let error):
            return "Transaction verification failed: \(error.localizedDescription)"
        case .purchaseFailed:
            return "Purchase could not be completed."
        }
    }
}
