import XCTest
@testable import DailyOK

/// Tests for subscription tier mapping and entitlement logic
final class SubscriptionServiceTests: XCTestCase {

    // MARK: - Product ID Constants

    func testProductIDsContainAllPlans() {
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.dailyok.caregiver.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.dailyok.caregiver.yearly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.dailyok.family.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.dailyok.family.yearly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.dailyok.familyplus.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.dailyok.familyplus.yearly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.dailyok.addon.receiver"))
        XCTAssertTrue(SubscriptionService.ProductIDs.all.contains("net.dailyok.addon.viewer"))
        XCTAssertEqual(SubscriptionService.ProductIDs.all.count, 8)
    }

    func testCaregiverProductIDs() {
        XCTAssertTrue(SubscriptionService.ProductIDs.caregiver.contains("net.dailyok.caregiver.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.caregiver.contains("net.dailyok.caregiver.yearly"))
        XCTAssertEqual(SubscriptionService.ProductIDs.caregiver.count, 2)
    }

    func testFamilyPlusProductIDs() {
        XCTAssertTrue(SubscriptionService.ProductIDs.familyPlus.contains("net.dailyok.familyplus.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.familyPlus.contains("net.dailyok.familyplus.yearly"))
        XCTAssertEqual(SubscriptionService.ProductIDs.familyPlus.count, 2)
    }

    func testFamilyProductIDs() {
        XCTAssertTrue(SubscriptionService.ProductIDs.family.contains("net.dailyok.family.monthly"))
        XCTAssertTrue(SubscriptionService.ProductIDs.family.contains("net.dailyok.family.yearly"))
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
        let purchased: Set<String> = ["net.dailyok.familyplus.monthly"]
        XCTAssertFalse(purchased.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.family))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.caregiver))
    }

    func testFamilyDetection() {
        let purchased: Set<String> = ["net.dailyok.family.yearly"]
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.familyPlus))
        XCTAssertFalse(purchased.isDisjoint(with: SubscriptionService.ProductIDs.family))
        XCTAssertTrue(purchased.isDisjoint(with: SubscriptionService.ProductIDs.caregiver))
    }

    func testCaregiverDetection() {
        let purchased: Set<String> = ["net.dailyok.caregiver.yearly"]
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
}
