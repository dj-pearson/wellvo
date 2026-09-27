import XCTest
@testable import DailyOK

/// The Family tab's rules (FamilyRoster): who takes a place, who can become
/// owner, which invites are waiting or expired, and the words shown.
final class FamilyRosterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let familyId = UUID()

    private func user(_ name: String, phone: String? = nil) -> AppUser {
        AppUser(
            id: UUID(), email: nil, phone: phone, displayName: name, role: .receiver,
            createdAt: now, updatedAt: now
        )
    }

    private func member(
        _ name: String?,
        role: UserRole,
        status: MemberStatus = .active,
        phone: String? = nil
    ) -> FamilyMember {
        FamilyMember(
            id: UUID(), familyId: familyId, userId: UUID(), role: role, status: status,
            invitedAt: nil, joinedAt: now,
            user: name.map { user($0, phone: phone) }
        )
    }

    private func invite(
        _ name: String,
        phone: String?,
        role: UserRole? = .receiver,
        createdDaysAgo: Double = 1,
        lifeDays: Double = 7,
        usedBy: UUID? = nil,
        expiresAt: Date? = nil
    ) -> PendingInvite {
        let created = now.addingTimeInterval(-createdDaysAgo * 86_400)
        return PendingInvite(
            id: UUID(), name: name, phone: phone, role: role, token: "ab12",
            checkinTime: "09:00:00", pairingCode: "123456",
            createdAt: created,
            expiresAt: expiresAt ?? created.addingTimeInterval(lifeDays * 86_400),
            usedBy: usedBy
        )
    }

    // MARK: - Places

    func testOpenInviteTakesAPlace() {
        // Caregiver plan, nobody joined, Mom invited: inviting Dad must hit the
        // limit now, not when Dad tries to join.
        let owner = member("Sam", role: .owner)
        let usage = FamilyRoster.usage(
            for: .receiver, members: [owner],
            openInvites: [invite("Mom", phone: "555-201-0001")], limit: 1
        )
        XCTAssertEqual(usage.used, 0)
        XCTAssertEqual(usage.waiting, 1)
        XCTAssertTrue(usage.isFull)
    }

    func testRemovedMembersDontTakeAPlace() {
        let usage = FamilyRoster.usage(
            for: .receiver,
            members: [member("Mom", role: .receiver, status: .deactivated)],
            openInvites: [], limit: 1
        )
        XCTAssertEqual(usage.taken, 0)
        XCTAssertFalse(usage.isFull)
    }

    func testInvitesCountPerRoleAndPerPerson() {
        let invites = [
            invite("Mom", phone: "(555) 201-0001"),
            invite("Mom again", phone: "+1 555 201 0001"),
            invite("Alex", phone: "555-201-0003", role: .viewer),
            invite("Old row", phone: "555-201-0004", role: nil), // no role column → receiver
        ]
        let receivers = FamilyRoster.usage(for: .receiver, members: [], openInvites: invites, limit: 3)
        let viewers = FamilyRoster.usage(for: .viewer, members: [], openInvites: invites, limit: 3)
        XCTAssertEqual(receivers.waiting, 2)
        XCTAssertEqual(viewers.waiting, 1)
    }

    func testStrayInviteToSomeoneAlreadySeatedIsNotCountedTwice() {
        let mom = member("Mom", role: .receiver, phone: "+15552010001")
        let usage = FamilyRoster.usage(
            for: .receiver, members: [mom],
            openInvites: [invite("Mom", phone: "555-201-0001")], limit: 2
        )
        XCTAssertEqual(usage.taken, 1)
    }

    // MARK: - Who can do what

    func testOnlyActiveCoCaregiversCanBecomeOwner() {
        XCTAssertTrue(FamilyRoster.canTransferOwnership(to: member("Alex", role: .viewer)))
        XCTAssertFalse(FamilyRoster.canTransferOwnership(to: member("Mom", role: .receiver)))
        XCTAssertFalse(FamilyRoster.canTransferOwnership(to: member("Alex", role: .viewer, status: .invited)))
        XCTAssertFalse(FamilyRoster.canTransferOwnership(to: member("Alex", role: .viewer, status: .deactivated)))
        XCTAssertFalse(FamilyRoster.canTransferOwnership(to: member("Sam", role: .owner)))
    }

    func testRemovedMembersCantBeRemovedOrOpened() {
        let removed = member("Mom", role: .receiver, status: .deactivated)
        XCTAssertFalse(FamilyRoster.canRemove(removed))
        XCTAssertFalse(FamilyRoster.opensSettings(removed, isOwner: true))
        XCTAssertFalse(FamilyRoster.canRemove(member("Sam", role: .owner)))
        XCTAssertTrue(FamilyRoster.canRemove(member("Alex", role: .viewer)))
    }

    func testOnlyTheOwnerOpensAReceiversSettings() {
        let mom = member("Mom", role: .receiver)
        XCTAssertTrue(FamilyRoster.opensSettings(mom, isOwner: true))
        XCTAssertFalse(FamilyRoster.opensSettings(mom, isOwner: false))
        XCTAssertFalse(FamilyRoster.opensSettings(member("Alex", role: .viewer), isOwner: true))
    }

    func testRemovedMemberIsNamedFromTheInviteTheyJoinedWith() {
        // RLS hides a removed member's user row, so the name and number for
        // "Invite Again" come from the invite they used.
        let removed = member(nil, role: .receiver, status: .deactivated)
        let older = invite("Mum", phone: "555-201-0001", createdDaysAgo: 20, usedBy: removed.userId)
        let newer = invite("Mom", phone: "555-201-0009", createdDaysAgo: 10, usedBy: removed.userId)
        let someoneElse = invite("Dad", phone: "555-201-0002", createdDaysAgo: 1, usedBy: UUID())
        let found = FamilyRoster.joinInvite(for: removed, in: [older, someoneElse, newer])
        XCTAssertEqual(found?.id, newer.id)
        XCTAssertNil(FamilyRoster.joinInvite(for: removed, in: [someoneElse]))
        XCTAssertNil(FamilyRoster.nonEmpty("  "))
        XCTAssertEqual(FamilyRoster.nonEmpty("Mom"), "Mom")
    }

    func testMembersAreOrderedOwnerReceiversViewersAndRemovedApart() {
        let list = [
            member("Zoe", role: .viewer),
            member("Mom", role: .receiver, status: .deactivated),
            member("Dad", role: .receiver),
            member("Sam", role: .owner),
            member("Ann", role: .receiver),
        ]
        XCTAssertEqual(FamilyRoster.currentMembers(list).compactMap { $0.user?.displayName },
                       ["Sam", "Ann", "Dad", "Zoe"])
        XCTAssertEqual(FamilyRoster.removedMembers(list).compactMap { $0.user?.displayName }, ["Mom"])
    }

    // MARK: - Waiting and expired invites

    func testResendShowsOnlyTheNewestInvitePerPerson() {
        let old = invite("Mom", phone: "555-201-0001", createdDaysAgo: 3, expiresAt: now.addingTimeInterval(-2 * 86_400))
        let new = invite("Mom", phone: "+1 (555) 201-0001", createdDaysAgo: 1)
        let parts = FamilyRoster.partitionInvites([old, new], members: [], now: now)
        XCTAssertEqual(parts.open.map(\.id), [new.id])
        XCTAssertTrue(parts.expired.isEmpty)
    }

    func testUnusedInviteThatRanOutShowsAsExpired() {
        let lapsed = invite("Dad", phone: "555-201-0002", createdDaysAgo: 9)
        let parts = FamilyRoster.partitionInvites([lapsed], members: [], now: now)
        XCTAssertTrue(parts.open.isEmpty)
        XCTAssertEqual(parts.expired.map(\.id), [lapsed.id])
    }

    func testCancelledInviteIsNotShownAsExpired() {
        let cancelled = invite(
            "Dad", phone: "555-201-0002", createdDaysAgo: 2,
            expiresAt: ISO8601DateFormatter().date(from: FamilyService.cancelledExpiry)
        )
        let parts = FamilyRoster.partitionInvites([cancelled], members: [], now: now)
        XCTAssertTrue(parts.open.isEmpty)
        XCTAssertTrue(parts.expired.isEmpty)
    }

    func testUsedInviteHidesOlderOnesAndExpiredIsDroppedOnceTheyJoined() {
        let usedNewest = invite("Mom", phone: "555-201-0001", createdDaysAgo: 1, usedBy: UUID())
        let olderLapsed = invite("Mom", phone: "555-201-0001", createdDaysAgo: 12)
        XCTAssertTrue(FamilyRoster.partitionInvites([usedNewest, olderLapsed], members: [], now: now).expired.isEmpty)

        let joinedAnotherWay = member("Dad", role: .receiver, phone: "5552010002")
        let lapsed = invite("Dad", phone: "555-201-0002", createdDaysAgo: 9)
        XCTAssertTrue(FamilyRoster.partitionInvites([lapsed], members: [joinedAnotherWay], now: now).expired.isEmpty)
    }

    func testExpiredOver30DaysAgoIsDropped() {
        let ancient = invite("Dad", phone: "555-201-0002", createdDaysAgo: 45)
        XCTAssertTrue(FamilyRoster.partitionInvites([ancient], members: [], now: now).expired.isEmpty)
    }

    func testExpiryIsCountedInCalendarDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        let evening = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 21))!
        // 9 AM tomorrow is "tomorrow", not "today" (the old 24-hour floor).
        let nineTomorrow = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 9))!
        XCTAssertEqual(FamilyRoster.expiryText(expiresAt: nineTomorrow, now: evening, calendar: cal), "expires tomorrow")
        // A fresh 7-day invite reads 7 days, not 6.
        let week = evening.addingTimeInterval(7 * 86_400 - 60)
        XCTAssertEqual(FamilyRoster.expiryText(expiresAt: week, now: evening, calendar: cal), "expires in 7 days")
        let later = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 23))!
        XCTAssertEqual(FamilyRoster.expiryText(expiresAt: later, now: evening, calendar: cal), "expires today")
    }

    func testInviteLinkMatchesTheServersFormat() {
        let row = invite("Mom", phone: "555-201-0001")
        XCTAssertEqual(row.inviteLink, "https://dailyok.net/invite/ab12?code=123456")
        let noToken = PendingInvite(
            id: UUID(), name: nil, phone: nil, checkinTime: nil, pairingCode: nil,
            createdAt: now, expiresAt: now, usedBy: nil
        )
        XCTAssertNil(noToken.inviteLink)
        XCTAssertEqual(noToken.invitedRole, .receiver)
    }

    func testInviteRowDecodesRoleAndToken() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Alex","phone":"5552010003","role":"viewer",
         "token":"cafe","checkin_time":null,"pairing_code":"654321",
         "created_at":"2026-09-20T12:00:00Z","expires_at":"2026-09-27T12:00:00Z","used_by":null}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(PendingInvite.self, from: Data(json.utf8))
        XCTAssertEqual(row.invitedRole, .viewer)
        XCTAssertEqual(row.inviteLink, "https://dailyok.net/invite/cafe?code=654321")
    }

    // MARK: - Words

    func testTierNamesAreReadable() {
        XCTAssertEqual(SubscriptionTier.familyPlus.displayName, "Family Plus")
        XCTAssertTrue(SubscriptionTier.familyPlus.isTopTier)
        XCTAssertFalse(SubscriptionTier.family.isTopTier)
    }

    func testLimitMessageNamesThePlanAndTheWaitingInvite() {
        let usage = FamilyRoster.SlotUsage(used: 0, waiting: 1, limit: 1)
        let text = FamilyRoster.limitMessage(for: .receiver, usage: usage, tier: .caregiver)
        XCTAssertTrue(text.contains("Caregiver plan covers 1 person"))
        XCTAssertTrue(text.contains("held by an invite"))
        XCTAssertTrue(text.contains("Upgrade"))

        let top = FamilyRoster.limitMessage(for: .receiver, usage: FamilyRoster.SlotUsage(used: 6, waiting: 0, limit: 6), tier: .familyPlus)
        XCTAssertFalse(top.contains("Upgrade"))

        let noViewers = FamilyRoster.limitMessage(for: .viewer, usage: FamilyRoster.SlotUsage(used: 0, waiting: 0, limit: 0), tier: .free)
        XCTAssertTrue(noViewers.contains("doesn't include co-caregivers"))
    }

    func testShareMessageForACaregiverNeverAsksThemToCheckIn() {
        let text = FamilyRoster.shareMessage(name: "Alex", role: .viewer, link: "https://dailyok.net/invite/x?code=1", code: "123456")
        XCTAssertTrue(text.contains("won't be asked to check in"))
        XCTAssertTrue(text.contains("123456"))
        let receiver = FamilyRoster.shareMessage(name: "Mom", role: .receiver, link: nil, code: nil)
        XCTAssertTrue(receiver.hasPrefix("Hi Mom!"))
    }

    // MARK: - Plan badge

    private func family(tier: SubscriptionTier, status: SubscriptionStatus, expires: Date? = nil, freeDeadline: Date? = nil) -> Family {
        Family(
            id: familyId, name: "Home", ownerId: UUID(), subscriptionTier: tier,
            subscriptionStatus: status, subscriptionExpiresAt: expires,
            freeTierExpiresAt: freeDeadline, maxReceivers: 1, maxViewers: 3, createdAt: now
        )
    }

    func testPlanState() {
        XCTAssertEqual(FamilyRoster.planState(family(tier: .caregiver, status: .active), now: now), .active)
        XCTAssertEqual(FamilyRoster.planState(family(tier: .caregiver, status: .gracePeriod), now: now), .renewSoon)
        XCTAssertEqual(FamilyRoster.planState(family(tier: .caregiver, status: .expired), now: now), .expired)
        let later = now.addingTimeInterval(86_400)
        XCTAssertEqual(FamilyRoster.planState(family(tier: .family, status: .cancelled, expires: later), now: now), .endsOn(later))
        XCTAssertEqual(FamilyRoster.planState(family(tier: .family, status: .cancelled, expires: nil), now: now), .expired)
        XCTAssertEqual(
            FamilyRoster.planState(family(tier: .free, status: .active, freeDeadline: now.addingTimeInterval(-1)), now: now),
            .expired
        )
    }
}
