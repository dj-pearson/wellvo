import Foundation
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var currentTier: SubscriptionTier = .free

    private let productIDs = [
        "net.wellvo.family.monthly",
        "net.wellvo.family.yearly",
        "net.wellvo.familyplus.monthly",
        "net.wellvo.familyplus.yearly",
        "net.wellvo.addon.receiver",
        "net.wellvo.addon.viewer",
    ]

    private var updateTask: Task<Void, Never>?

    init() {
        updateTask = Task {
            await listenForTransactions()
        }
    }

    deinit {
        updateTask?.cancel()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error.localizedDescription)")
        }
    }

    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            return nil

        @unknown default:
            return nil
        }
    }

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchased
        updateCurrentTier()
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - Private

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result) {
                await updatePurchasedProducts()
                await transaction.finish()

                // Sync to backend
                await syncSubscriptionToBackend(transaction)
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let item):
            return item
        }
    }

    private func updateCurrentTier() {
        if purchasedProductIDs.contains(where: { $0.contains("familyplus") }) {
            currentTier = .familyPlus
        } else if purchasedProductIDs.contains(where: { $0.contains("family") }) {
            currentTier = .family
        } else {
            currentTier = .free
        }
    }

    private func syncSubscriptionToBackend(_ transaction: StoreKit.Transaction) async {
        do {
            try await SupabaseService.shared.client.functions.invoke(
                "subscription-webhook",
                options: .init(body: [
                    "product_id": transaction.productID,
                    "transaction_id": String(transaction.id),
                    "original_id": String(transaction.originalID),
                    "expiration_date": transaction.expirationDate?.ISO8601Format() ?? "",
                ])
            )
        } catch {
            print("Failed to sync subscription: \(error.localizedDescription)")
        }
    }
}

enum SubscriptionError: LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed: return "Transaction verification failed"
        }
    }
}
