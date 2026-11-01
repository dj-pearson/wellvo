import XCTest
@testable import DailyOK

/// Onboarding never creates a duplicate family.
///
/// The owner could go Back from the plan step and tap Continue again, and each
/// tap inserted another `families` row. Invites then targeted the newest
/// family while `getFamily()` resolves to the earliest one, so the invited
/// receiver never appeared on the dashboard. A failed `family_members` insert
/// after a successful family insert did the same on retry.
@MainActor
final class OnboardingViewModelFamilyTests: XCTestCase {

    /// Records every call the view model makes, and lets a test script the
    /// server's state and failures.
    private final class FakeFamilyBackend {
        var ownedOnServer: Family?
        var insertCount = 0
        var renames: [(UUID, String)] = []
        var membershipCalls: [UUID] = []
        var membershipFailuresRemaining = 0

        var dependencies: OnboardingFamilyDependencies {
            OnboardingFamilyDependencies(
                findOwnedFamily: { self.ownedOnServer },
                insertFamily: { name in
                    self.insertCount += 1
                    let family = OnboardingViewModelFamilyTests.makeFamily(name: name)
                    self.ownedOnServer = self.ownedOnServer ?? family
                    return family
                },
                renameFamily: { id, name in
                    self.renames.append((id, name))
                    let renamed = OnboardingViewModelFamilyTests.makeFamily(id: id, name: name)
                    self.ownedOnServer = renamed
                    return renamed
                },
                ensureOwnerMembership: { familyId in
                    self.membershipCalls.append(familyId)
                    if self.membershipFailuresRemaining > 0 {
                        self.membershipFailuresRemaining -= 1
                        throw MembershipFailed()
                    }
                }
            )
        }
    }

    private struct MembershipFailed: Error {}

    nonisolated static func makeFamily(id: UUID = UUID(), name: String) -> Family {
        Family(
            id: id,
            name: name,
            ownerId: UUID(),
            subscriptionTier: .free,
            subscriptionStatus: .active,
            subscriptionExpiresAt: nil,
            freeTierExpiresAt: nil,
            maxReceivers: 1,
            maxViewers: 0,
            createdAt: Date()
        )
    }

    private func makeViewModel(_ backend: FakeFamilyBackend, name: String = "Smith") -> OnboardingViewModel {
        let viewModel = OnboardingViewModel()
        viewModel.familyDependencies = backend.dependencies
        viewModel.currentStep = .createFamily
        viewModel.familyName = name
        return viewModel
    }

    // MARK: - First run

    func testFirstCreateInsertsOnceAndAdvances() async {
        let backend = FakeFamilyBackend()
        let viewModel = makeViewModel(backend)

        await viewModel.createFamily()

        XCTAssertEqual(backend.insertCount, 1)
        XCTAssertEqual(backend.membershipCalls, [viewModel.createdFamily?.id].compactMap { $0 })
        XCTAssertEqual(viewModel.currentStep, .choosePlan)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - The regression

    func testGoingBackAndContinuingAgainReusesTheFamily() async {
        let backend = FakeFamilyBackend()
        let viewModel = makeViewModel(backend)

        await viewModel.createFamily()
        let first = viewModel.createdFamily
        viewModel.goBack()
        XCTAssertEqual(viewModel.currentStep, .createFamily)
        await viewModel.createFamily()

        XCTAssertEqual(backend.insertCount, 1, "A second Continue must not insert another families row.")
        XCTAssertEqual(viewModel.createdFamily?.id, first?.id)
        XCTAssertTrue(backend.renames.isEmpty, "Same name — nothing to rename.")
        XCTAssertEqual(viewModel.currentStep, .choosePlan)
    }

    func testEditingTheNameAfterGoingBackRenamesInsteadOfInserting() async {
        let backend = FakeFamilyBackend()
        let viewModel = makeViewModel(backend)

        await viewModel.createFamily()
        let firstId = viewModel.createdFamily?.id
        viewModel.goBack()
        viewModel.familyName = "  The Smiths  "
        await viewModel.createFamily()

        XCTAssertEqual(backend.insertCount, 1)
        XCTAssertEqual(backend.renames.count, 1)
        XCTAssertEqual(backend.renames.first?.0, firstId)
        XCTAssertEqual(backend.renames.first?.1, "The Smiths")
        XCTAssertEqual(viewModel.createdFamily?.id, firstId)
        XCTAssertEqual(viewModel.createdFamily?.name, "The Smiths")
        XCTAssertEqual(viewModel.currentStep, .choosePlan)
    }

    func testAnAlreadyOwnedFamilyOnTheServerIsReused() async {
        let backend = FakeFamilyBackend()
        let existing = Self.makeFamily(name: "Smith")
        backend.ownedOnServer = existing
        let viewModel = makeViewModel(backend)

        await viewModel.createFamily()

        XCTAssertEqual(backend.insertCount, 0)
        XCTAssertEqual(viewModel.createdFamily?.id, existing.id)
        XCTAssertEqual(backend.membershipCalls, [existing.id])
        XCTAssertEqual(viewModel.currentStep, .choosePlan)
    }

    func testAFailedMembershipInsertIsRetriedAgainstTheSameFamily() async {
        let backend = FakeFamilyBackend()
        backend.membershipFailuresRemaining = 1
        let viewModel = makeViewModel(backend)

        await viewModel.createFamily()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.currentStep, .createFamily, "Must not advance without the owner's membership row.")
        XCTAssertFalse(viewModel.isLoading)
        let firstId = viewModel.createdFamily?.id
        XCTAssertNotNil(firstId, "The inserted family is remembered so the retry reuses it.")

        await viewModel.createFamily()

        XCTAssertEqual(backend.insertCount, 1, "The retry must not insert a duplicate family.")
        XCTAssertEqual(backend.membershipCalls, [firstId, firstId].compactMap { $0 })
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.currentStep, .choosePlan)
    }

    // MARK: - Validation still short-circuits

    func testAnEmptyNameMakesNoCalls() async {
        let backend = FakeFamilyBackend()
        let viewModel = makeViewModel(backend, name: "   ")

        await viewModel.createFamily()

        XCTAssertEqual(backend.insertCount, 0)
        XCTAssertTrue(backend.membershipCalls.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.currentStep, .createFamily)
    }
}
