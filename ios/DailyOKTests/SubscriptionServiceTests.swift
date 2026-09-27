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

// MARK: - Settings tab (2026-09-27 deep dive)

/// The Settings tab's rules: what the plan row says, when this Apple ID's
/// subscription needs explaining, restore outcomes, and role-specific copy.
final class SettingsPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let me = UUID()
    private let sibling = UUID()

    private func family(
        tier: SubscriptionTier,
        status: SubscriptionStatus = .active,
        expires: Date? = nil,
        freeDeadline: Date? = nil,
        payer: UUID? = nil
    ) -> Family {
        var f = Family(
            id: UUID(), name: "Home", ownerId: me, subscriptionTier: tier,
            subscriptionStatus: status, subscriptionExpiresAt: expires,
            freeTierExpiresAt: freeDeadline, maxReceivers: 3, maxViewers: 5, createdAt: now
        )
        f.billingUserId = payer
        return f
    }

    // MARK: Plan row

    func testPlanLineUsesTheFamilysPlanAndDisplayName() {
        let line = PlanSummary.line(for: family(tier: .familyPlus, expires: now.addingTimeInterval(86_400 * 10)), now: now)
        XCTAssertEqual(line.title, "Family Plus") // never "Family_plus"
        XCTAssertFalse(line.needsAttention)
        XCTAssertNotNil(line.detail)
    }

    func testPlanLineFlagsPaymentIssueExpiryAndFreeDeadline() {
        let grace = PlanSummary.line(for: family(tier: .family, status: .gracePeriod, expires: now), now: now)
        XCTAssertTrue(grace.needsAttention)
        XCTAssertTrue(grace.detail?.contains("Payment issue") ?? false)

        let expired = PlanSummary.line(for: family(tier: .family, status: .expired), now: now)
        XCTAssertTrue(expired.needsAttention)
        XCTAssertTrue(expired.detail?.contains("paused") ?? false)

        let freeEnding = PlanSummary.line(for: family(tier: .free, freeDeadline: now.addingTimeInterval(86_400)), now: now)
        XCTAssertFalse(freeEnding.needsAttention)
        XCTAssertTrue(freeEnding.detail?.contains("Free until") ?? false)

        let freeEnded = PlanSummary.line(for: family(tier: .free, freeDeadline: now.addingTimeInterval(-1)), now: now)
        XCTAssertTrue(freeEnded.needsAttention)
    }

    // MARK: This Apple ID vs. the family

    func testNewOwnerAfterTransferIsNotUpsoldAPlanASiblingPays() {
        let paidBySibling = family(tier: .family, expires: now.addingTimeInterval(86_400 * 20), payer: sibling)
        XCTAssertEqual(
            PlanSummary.storeRelation(storeTier: .free, family: paidBySibling, currentUserId: me, isOwner: true, now: now),
            .paidByAnotherMember
        )
    }

    func testExOwnerStillPayingIsToldWhereToCancelWhenItNoLongerCovers() {
        let ownedByOther = family(tier: .family, expires: now.addingTimeInterval(86_400), payer: sibling)
        XCTAssertEqual(
            PlanSummary.storeRelation(storeTier: .family, family: ownedByOther, currentUserId: me, isOwner: false, now: now),
            .payingForNothing(.family)
        )
        // …but a co-caregiver whose subscription does pay for the family is fine.
        let paidByMe = family(tier: .family, expires: now.addingTimeInterval(86_400), payer: me)
        XCTAssertEqual(
            PlanSummary.storeRelation(storeTier: .family, family: paidByMe, currentUserId: me, isOwner: false, now: now),
            .consistent
        )
    }

    func testAnUnappliedEntitlementPointsToRestore() {
        XCTAssertEqual(
            PlanSummary.storeRelation(storeTier: .familyPlus, family: family(tier: .caregiver, expires: now.addingTimeInterval(86_400)), currentUserId: me, isOwner: true, now: now),
            .notAppliedYet(.familyPlus)
        )
        XCTAssertEqual(
            PlanSummary.storeRelation(storeTier: .family, family: family(tier: .family, status: .expired), currentUserId: me, isOwner: true, now: now),
            .notAppliedYet(.family)
        )
        XCTAssertEqual(
            PlanSummary.storeRelation(storeTier: .family, family: family(tier: .family, expires: now.addingTimeInterval(86_400)), currentUserId: me, isOwner: true, now: now),
            .consistent
        )
    }

    func testPaidOnAnotherAppleIDIsExplainedToTheOwner() {
        XCTAssertEqual(
            PlanSummary.storeRelation(storeTier: .free, family: family(tier: .family, expires: now.addingTimeInterval(86_400)), currentUserId: me, isOwner: true, now: now),
            .paidElsewhere
        )
        XCTAssertNil(PlanSummary.relationMessage(.consistent))
        XCTAssertNotNil(PlanSummary.relationMessage(.payingForNothing(.caregiver)))
    }

    // MARK: Restore / sync outcomes

    func testRestoreOutcomes() {
        XCTAssertEqual(SubscriptionService.restoreOutcome(tier: .family, storeSyncFailed: false, backendMessage: nil), .restored(.family))
        XCTAssertEqual(SubscriptionService.restoreOutcome(tier: .free, storeSyncFailed: false, backendMessage: nil), .nothingToRestore)
        if case .failed = SubscriptionService.restoreOutcome(tier: .free, storeSyncFailed: true, backendMessage: nil) {} else {
            XCTFail("An App Store failure with nothing on the device is a failure, not 'nothing found'")
        }
        XCTAssertEqual(
            SubscriptionService.restoreOutcome(tier: .family, storeSyncFailed: false, backendMessage: "x"),
            .failed("x")
        )
    }

    func testRevokedAndUpgradedTransactionsAreNotPushedAsActive() {
        XCTAssertTrue(SubscriptionService.shouldSyncToBackend(revoked: false, upgraded: false))
        XCTAssertFalse(SubscriptionService.shouldSyncToBackend(revoked: true, upgraded: false))
        XCTAssertFalse(SubscriptionService.shouldSyncToBackend(revoked: false, upgraded: true))
    }

    func testRejectionMessagesNeverShowServerText() {
        let body = #"{"error":"This purchase is already linked to another Daily OK account"}"#
        let m = SubscriptionService.rejectionMessage(status: 409, body: body)
        XCTAssertFalse(m.contains("{"))
        XCTAssertTrue(m.contains("different Daily OK account"))
        XCTAssertTrue(SubscriptionService.rejectionMessage(status: 409, body: #"{"error":"addon_unavailable"}"#).contains("Extra places"))
        XCTAssertTrue(SubscriptionService.rejectionMessage(status: 404, body: nil).contains("Restore Purchases"))
    }

    func testPaywallGroupsPlansMonthlyThenYearly() {
        let ids: [(String, Decimal)] = [
            (SubscriptionService.ProductIDs.familyPlusMonthly, 9.99),
            (SubscriptionService.ProductIDs.caregiverYearly, 29.99),
            (SubscriptionService.ProductIDs.familyMonthly, 5.99),
            (SubscriptionService.ProductIDs.caregiverMonthly, 3.99),
        ]
        let sorted = ids.sorted { SubscriptionService.paywallOrder($0.0, $0.1) < SubscriptionService.paywallOrder($1.0, $1.1) }
        XCTAssertEqual(sorted.map(\.0), [
            SubscriptionService.ProductIDs.caregiverMonthly,
            SubscriptionService.ProductIDs.caregiverYearly,
            SubscriptionService.ProductIDs.familyMonthly,
            SubscriptionService.ProductIDs.familyPlusMonthly,
        ])
    }

    func testSeatsMatchTheServerTierMap() {
        XCTAssertEqual(PlanSummary.seats(for: .caregiver)?.people, 1)
        XCTAssertEqual(PlanSummary.seats(for: .family)?.coCaregivers, 5)
        XCTAssertEqual(PlanSummary.seats(for: .familyPlus)?.people, 6)
        XCTAssertNil(PlanSummary.seats(for: .free))
        XCTAssertEqual(PlanSummary.seatsLine(people: 1, coCaregivers: 3), "Check on 1 person · 3 co-caregivers")
    }

    // MARK: Account copy

    func testSignOutWarnsCaregiversAboutAlerts() {
        XCTAssertTrue(AccountCopy.signOutMessage(role: .owner).contains("won't alert you"))
        XCTAssertTrue(AccountCopy.signOutMessage(role: .viewer).contains("won't alert you"))
        XCTAssertTrue(AccountCopy.signOutMessage(role: .receiver).contains("check-in notifications"))
    }

    func testDeleteCopyFitsTheRoleAndMentionsBilling() {
        XCTAssertTrue(AccountCopy.deleteMessage(role: .owner, hasStoreSubscription: false).contains("your family"))
        XCTAssertTrue(AccountCopy.deleteMessage(role: .viewer, hasStoreSubscription: false).contains("stay with the owner"))
        XCTAssertFalse(AccountCopy.deleteMessage(role: .viewer, hasStoreSubscription: false).contains("App Store"))
        XCTAssertTrue(AccountCopy.deleteMessage(role: .owner, hasStoreSubscription: true).contains("not cancelled"))
    }

    func testFailureCopyIsPlain() {
        let offline = AccountCopy.failureMessage(for: URLError(.notConnectedToInternet), action: "delete your account")
        XCTAssertTrue(offline.contains("offline"))
        let other = AccountCopy.failureMessage(for: NSError(domain: "PostgrestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"]), action: "delete your account")
        XCTAssertFalse(other.contains("Unauthorized"))
    }

    func testAppleLinkConflictReadsPlainly() {
        let error = EdgeFunctionsClient.HTTPError(status: 409, body: #"{"error":"This Apple ID is already linked to an account"}"#)
        let message = AuthViewModel.appleLinkFailureMessage(error)
        XCTAssertFalse(message.contains("Edge function error"))
        XCTAssertTrue(message.contains("another Daily OK account"))
    }

    // MARK: Retention and export

    func testRetentionShorteningIsDetected() {
        XCTAssertTrue(PlanSummary.retentionShortens(from: 730, to: 90))
        XCTAssertFalse(PlanSummary.retentionShortens(from: 90, to: 365))
        XCTAssertFalse(PlanSummary.retentionShortens(from: nil, to: 90))
    }

    func testExportFileIsDatedJSON() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        XCTAssertEqual(PlanSummary.exportFileName(now: date, calendar: cal), "DailyOK-export-2026-09-07.json")
    }

    // MARK: Decoding

    func testFamilyDecodesWithAndWithoutBillingUser() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let base = """
        {"id":"\(UUID().uuidString)","name":"Home","owner_id":"\(me.uuidString)","subscription_tier":"family",
         "subscription_status":"active","max_receivers":3,"max_viewers":5,"created_at":"2026-01-01T00:00:00Z"
        """
        let old = try decoder.decode(Family.self, from: Data((base + "}").utf8))
        XCTAssertNil(old.billingUserId)
        let new = try decoder.decode(Family.self, from: Data((base + #","billing_user_id":"\#(sibling.uuidString)"}"#).utf8))
        XCTAssertEqual(new.billingUserId, sibling)
    }
}
