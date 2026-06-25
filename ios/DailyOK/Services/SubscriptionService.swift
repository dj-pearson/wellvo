import Foundation
import os
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var currentTier: SubscriptionTier = .free
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// The grandfather deadline for a legacy Free-tier family, mirrored from the
    /// loaded `Family` so feature gating can honor it (US-IOS097). Set this when
    /// the family loads. nil = no grandfather window.
    @Published var freeTierExpiresAt: Date?

    /// Whether the grandfathered Free-tier window has lapsed.
    var isFreeTierExpired: Bool {
        guard currentTier == .free, let deadline = freeTierExpiresAt else { return false }
        return deadline < Date()
    }

    // MARK: - Product IDs (update these to match your App Store Connect configuration)

    struct ProductIDs {
        static let caregiverMonthly = "net.wellvo.caregiver.monthly"
        static let caregiverYearly = "net.wellvo.caregiver.yearly"
        static let familyMonthly = "net.wellvo.family.monthly"
        static let familyYearly = "net.wellvo.family.yearly"
        static let familyPlusMonthly = "net.wellvo.familyplus.monthly"
        static let familyPlusYearly = "net.wellvo.familyplus.yearly"
        static let addonReceiver = "net.wellvo.addon.receiver"
        static let addonViewer = "net.wellvo.addon.viewer"

        static let all: Set<String> = [
            caregiverMonthly, caregiverYearly,
            familyMonthly, familyYearly,
            familyPlusMonthly, familyPlusYearly,
            addonReceiver, addonViewer,
        ]

        static let familyPlus: Set<String> = [familyPlusMonthly, familyPlusYearly]
        static let family: Set<String> = [familyMonthly, familyYearly]
        static let caregiver: Set<String> = [caregiverMonthly, caregiverYearly]
    }

    private var updateTask: Task<Void, Never>?
    /// Guards the once-per-launch backend reconcile so foregrounding doesn't
    /// re-push entitlements on every resume.
    private var hasReconciledThisLaunch = false

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
            Log.subscription.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    // MARK: - Display Pricing (StoreKit-driven, App Store guideline 3.1)

    /// The locale-aware display price for a product id (e.g. "$3.99", "3,99 €"),
    /// or `nil` until `loadProducts()` has populated `products`. Never hardcode
    /// prices — they must match what StoreKit will actually charge.
    func displayPrice(for productID: String) -> String? {
        products.first { $0.id == productID }?.displayPrice
    }

    /// Display price with the renewal period suffix derived from StoreKit, e.g.
    /// "$3.99/mo". Returns `nil` until products load so callers can show a
    /// placeholder rather than a stale hardcoded price.
    func displayPriceWithPeriod(for productID: String) -> String? {
        guard let product = products.first(where: { $0.id == productID }) else { return nil }
        // Non-subscription products (the add-ons) have no renewal period — show
        // the bare price.
        return Self.priceWithPeriod(
            displayPrice: product.displayPrice,
            periodUnit: product.subscription?.subscriptionPeriod.unit
        )
    }

    /// Short suffix for a StoreKit renewal-period unit ("mo", "yr", …). Extracted
    /// as a pure function so the mapping — including the `@unknown default`
    /// fallback for a future unit — is unit-testable without a live StoreKit
    /// product (US-IOS110). An unknown unit returns "" so callers drop the suffix
    /// and show the bare price rather than a malformed "$3.99/".
    nonisolated static func periodSuffix(for unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "day"
        case .week: return "wk"
        case .month: return "mo"
        case .year: return "yr"
        @unknown default: return ""
        }
    }

    /// Compose a locale-aware display price with an optional renewal-period
    /// suffix, e.g. "$3.99" + `.month` → "$3.99/mo". A `nil` unit (non-subscription
    /// product) or an unknown future unit yields the bare price. Pure/testable.
    nonisolated static func priceWithPeriod(
        displayPrice: String,
        periodUnit: Product.SubscriptionPeriod.Unit?
    ) -> String {
        guard let periodUnit else { return displayPrice }
        let suffix = periodSuffix(for: periodUnit)
        return suffix.isEmpty ? displayPrice : "\(displayPrice)/\(suffix)"
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

            // Sync to the backend BEFORE finishing the transaction. If we finish
            // first and the process is killed mid-sync, StoreKit can't redeliver
            // (it's already finished) and the family stays un-upgraded until a
            // manual restore (US-IOS095). Finishing after the sync means an
            // interrupted sync leaves the transaction unfinished, so it's
            // redelivered via Transaction.updates / currentEntitlements.
            await syncSubscriptionToBackend(transaction)
            await transaction.finish()

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
        // Restore must also re-provision the backend: a reinstalled user has a
        // valid StoreKit entitlement but the server never recorded it, so
        // without this their seats/features never come back (US-IOS095).
        await reconcileEntitlementsToBackend()
        isLoading = false
    }

    /// Push every currently-entitled transaction to the backend so a
    /// verified-but-unsynced subscription (reinstall, interrupted purchase,
    /// restore) provisions server-side without a fresh purchase. The webhook is
    /// idempotent, so re-sending an already-recorded entitlement is harmless.
    /// Safe to call on launch and after restore.
    /// Once-per-launch reconcile, safe to call on every foreground.
    func reconcileEntitlementsToBackendOnce() async {
        guard !hasReconciledThisLaunch else { return }
        hasReconciledThisLaunch = true
        await reconcileEntitlementsToBackend()
    }

    func reconcileEntitlementsToBackend() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }
            await syncSubscriptionToBackend(transaction)
        }
    }

    /// Check if the user has access to a specific feature tier.
    ///
    /// Tier precedence (higher includes lower):
    /// `familyPlus` > `family` > `caregiver` > `free`
    ///
    /// Note: `.free` is a legacy grandfathered state — new signups never see
    /// it. Feature gating should generally check against `.caregiver` as the
    /// baseline paid tier.
    func hasAccess(to tier: SubscriptionTier) -> Bool {
        switch tier {
        case .free:
            return true
        case .caregiver:
            // A grandfathered Free-tier family keeps Caregiver-level access until
            // its free window lapses; once expired, paid features are gated and
            // the owner is prompted to upgrade (US-IOS097).
            if currentTier == .free {
                return freeTierExpiresAt != nil && !isFreeTierExpired
            }
            return currentTier == .caregiver
                || currentTier == .family
                || currentTier == .familyPlus
        case .family:
            return currentTier == .family || currentTier == .familyPlus
        case .familyPlus:
            return currentTier == .familyPlus
        }
    }

    /// The tier a subscription product belongs to (nil for add-ons).
    func tier(forProductID id: String) -> SubscriptionTier? {
        if ProductIDs.familyPlus.contains(id) { return .familyPlus }
        if ProductIDs.family.contains(id) { return .family }
        if ProductIDs.caregiver.contains(id) { return .caregiver }
        return nil
    }

    /// Relationship of a plan row to the active tier, for paywall labeling
    /// (US-IOS096).
    enum PlanRelation { case current, upgrade, switchPlan, none }

    func relation(forProductID id: String) -> PlanRelation {
        if purchasedProductIDs.contains(id) { return .current }
        guard let rowTier = tier(forProductID: id), currentTier != .free else { return .none }
        let rank: (SubscriptionTier) -> Int = {
            switch $0 { case .free: return 0; case .caregiver: return 1; case .family: return 2; case .familyPlus: return 3 }
        }
        if rank(rowTier) > rank(currentTier) { return .upgrade }
        return .switchPlan // same-tier different billing, or a downgrade
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

    /// Determine the current tier using exact product ID matching (not substring).
    /// Precedence: `familyPlus` > `family` > `caregiver` > `free`.
    private func updateCurrentTier() {
        if !purchasedProductIDs.isDisjoint(with: ProductIDs.familyPlus) {
            currentTier = .familyPlus
        } else if !purchasedProductIDs.isDisjoint(with: ProductIDs.family) {
            currentTier = .family
        } else if !purchasedProductIDs.isDisjoint(with: ProductIDs.caregiver) {
            currentTier = .caregiver
        } else {
            currentTier = .free
        }
    }

    /// Sync subscription status to the Supabase backend with exponential backoff retry
    private func syncSubscriptionToBackend(_ transaction: StoreKit.Transaction, attempt: Int = 1) async {
        let maxRetries = 3
        do {
            try await EdgeFunctionsClient.invoke(
                "subscription-webhook",
                body: [
                    "product_id": transaction.productID,
                    "transaction_id": String(transaction.id),
                    "original_id": String(transaction.originalID),
                    "expiration_date": transaction.expirationDate?.ISO8601Format() ?? "",
                    "app_account_token": transaction.appAccountToken?.uuidString ?? "",
                ]
            )
        } catch {
            if attempt < maxRetries {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000 // exponential backoff
                try? await Task.sleep(nanoseconds: delay)
                await syncSubscriptionToBackend(transaction, attempt: attempt + 1)
            } else {
                Log.subscription.error("Failed to sync subscription after \(maxRetries, privacy: .public) attempts: \(error.localizedDescription, privacy: .public)")
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
