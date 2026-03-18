import XCTest
@testable import Wellvo

/// Tests for subscription tier mapping and entitlement logic
final class SubscriptionServiceTests: XCTestCase {

    // MARK: - Product ID Constants

    func testProductIDsContainAllPlans() {
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.family.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.family.yearly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.familyplus.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.familyplus.yearly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.addon.receiver"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.wellvo.addon.viewer"))
        XCTAssertEqual(SubscriptionService.ProductIDs.all.count, 6)
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

    // MARK: - Subscription Tier Raw Values

    func testSubscriptionTierRawValues() {
        XCTAssertEqual(SubscriptionTier.free.rawValue, "free")
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
        // Should not be disjoint with familyPlus set
        XCTAssertFalse(purchased.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        // Should be disjoint with family set
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.family))
    }

    func testFamilyDetection() {
        let purchased: Set<String> = ["net.wellvo.family.yearly"]
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        XCTAssertFalse(purchased.isDisjoint(with: SubscriptionService.ProductIDs.family))
    }

    func testFreeDetection() {
        let purchased: Set<String> = []
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.family))
    }
}
