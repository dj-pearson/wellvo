import XCTest
import StoreKit
@testable import DailyOK

/// Tests for subscription tier mapping and entitlement logic
final class SubscriptionServiceTests: XCTestCase {

    // MARK: - StoreKit-driven display pricing (US-IOS044 / US-IOS110)

    func testPeriodSuffixForEachKnownUnit() {
        // A non-.month unit must format too — App Store guideline 3.1 prices have
        // to reflect the real renewal period, not a hardcoded "/mo".
        XCTAssertEqual(SubscriptionService.periodSuffix(for: .day), "day")
        XCTAssertEqual(SubscriptionService.periodSuffix(for: .week), "wk")
        XCTAssertEqual(SubscriptionService.periodSuffix(for: .month), "mo")
        XCTAssertEqual(SubscriptionService.periodSuffix(for: .year), "yr")
    }

    func testPriceWithPeriodComposesSuffix() {
        XCTAssertEqual(
            SubscriptionService.priceWithPeriod(displayPrice: "$3.99", periodUnit: .month),
            "$3.99/mo"
        )
        XCTAssertEqual(
            SubscriptionService.priceWithPeriod(displayPrice: "59,99 €", periodUnit: .year),
            "59,99 €/yr"
        )
        // A locale-formatted price string is passed through untouched aside from
        // the appended suffix (no hardcoded currency assumptions).
        XCTAssertEqual(
            SubscriptionService.priceWithPeriod(displayPrice: "￥600", periodUnit: .week),
            "￥600/wk"
        )
    }

    func testPriceWithPeriodReturnsBarePriceForNonSubscriptionProduct() {
        // nil period unit = a one-time add-on (no renewal) -> no "/" suffix, never
        // a malformed "$0.99/".
        XCTAssertEqual(
            SubscriptionService.priceWithPeriod(displayPrice: "$0.99", periodUnit: nil),
            "$0.99"
        )
    }

    // Note: the `@unknown default` branch of `periodSuffix` (a hypothetical future
    // StoreKit unit) is unreachable from a test — the enum has no inhabitant to
    // construct — but `priceWithPeriod` documents/guards its effect: an empty
    // suffix collapses to the bare price, verified above via the nil-unit path.

    // MARK: - Product ID Constants

    func testProductIDsContainAllPlans() {
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.caregiver.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.caregiver.yearly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.family.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.family.yearly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.familyplus.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.familyplus.yearly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.addon.receiver"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.addon.viewer"))
        XCTAssertEqual(SubscriptionService.ProductIDs.all.count, 8)
    }

    func testCaregiverProductIDs() {
        XCTAssertTrue(SubscriptionService.ProductIDs.caregiver.contains("net.wellvo.caregiver.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.caregiver.contains("net.wellvo.caregiver.yearly"))
        XCTAssertEqual(SubscriptionService.ProductIDs.caregiver.count, 2)
    }

    func testFamilyPlusProductIDs() {
        XCTAssertTrue(SubscriptionService.ProductIDs.familyPlus.contains("net.wellvo.familyplus.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.familyPlus.contains("net.wellvo.familyplus.yearly"))
        XCTAssertEqual(SubscriptionService.ProductIDs.familyPlus.count, 2)
    }

    func testFamilyProductIDs() {
        XCTAssertTrue(SubscriptionService.ProductIDs.family.contains("net.wellvo.family.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.family.contains("net.wellvo.family.yearly"))
        XCTAssertEqual(SubscriptionService.ProductIDs.family.count, 2)
    }

    func testTierSetsAreDisjoint() {
        XCTAssertTrue(SubscriptionService.ProductIDs.caregiver.isDisjoint(with: SubscriptionService.ProductIDs.family))
        XCTAssertTrue(SubscriptionService.ProductIDs.caregiver.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        XCTAssertTrue(SubscriptionService.ProductIDs.family.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
    }

    // MARK: - Subscription Tier Raw Values

    func testSubscriptionTierRawValues() {
        XCTAssertEqual(SubscriptionTier.free.rawValue, "free")
        XCTAssertEqual(SubscriptionTier.caregiver.rawValue, "caregiver")
        XCTAssertEqual(SubscriptionTier.family.rawValue, "family")
        XCTAssertEqual(SubscriptionTier.familyPlus.rawValue, "family_plus")
    }

    func testSubscriptionStatusRawValues() {
        XCTAssertEqual(SubscriptionStatus.active.rawValue, "active")
        XCTAssertEqual(SubscriptionStatus.expired.rawValue, "expired")
        XCTAssertEqual(SubscriptionStatus.gracePeriod.rawValue, "grace_period")
        XCTAssertEqual(SubscriptionStatus.cancelled.rawValue, "cancelled")
    }

    // MARK: - Tier Disjoint Set Logic

    func testFamilyPlusDetection() {
        let purchased: Set<String> = ["net.wellvo.familyplus.monthly"]
        XCTAssertFalse(purchased.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.family))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.caregiver))
    }

    func testFamilyDetection() {
        let purchased: Set<String> = ["net.wellvo.family.yearly"]
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        XCTAssertFalse(purchased.isDisjoint(with: SubscriptionService.ProductIDs.family))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.caregiver))
    }

    func testCaregiverDetection() {
        let purchased: Set<String> = ["net.wellvo.caregiver.yearly"]
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.family))
        XCTAssertFalse(purchased.isDisjoint(with: SubscriptionService.ProductIDs.caregiver))
    }

    func testFreeDetection() {
        let purchased: Set<String> = []
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.family))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.caregiver))
    }

    // MARK: - Finishing a transaction is gated on the sync outcome (US-IOS139)

    /// `Transaction.updates` only ever redelivers transactions that were never
    /// finished. So finishing one whose backend sync failed is the moment a paid
    /// subscription becomes permanently invisible to the server: StoreKit
    /// considers it handled and never mentions it again. Both the purchase path
    /// and the renewal listener call `finish()` only when this says they may.

    func testSyncedTransactionMayBeFinished() {
        XCTAssertTrue(SubscriptionService.SyncOutcome.synced.mayFinishTransaction)
    }

    /// The bug this replaced: the sync swallowed its failure, so this case was
    /// indistinguishable from success and the transaction was finished anyway.
    func testTransientFailureMustNotFinishTheTransaction() {
        XCTAssertFalse(SubscriptionService.SyncOutcome.transientFailure.mayFinishTransaction)
    }

    /// A deterministic 4xx will not succeed on the tenth launch either. Holding
    /// the transaction open would mean StoreKit redelivering it on every launch
    /// forever, so it is finished and surfaced to the user instead — the same
    /// dead-letter reasoning as the offline check-in queue (US-IOS099).
    func testPermanentRejectionFinishesRatherThanRedeliveringForever() {
        XCTAssertTrue(SubscriptionService.SyncOutcome.permanentlyRejected.mayFinishTransaction)
    }

    /// Exactly one outcome holds the transaction open. If a future case is added
    /// without deciding this, that is a paid subscription silently lost or a
    /// redelivery loop — neither should be reachable by accident.
    func testOnlyTransientFailureHoldsATransactionOpen() {
        let held: [SubscriptionService.SyncOutcome] = [.synced, .transientFailure, .permanentlyRejected]
            .filter { !$0.mayFinishTransaction }
        XCTAssertEqual(held.count, 1)
    }
}
