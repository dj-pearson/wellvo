import SwiftUI
import CoreImage.CIFilterBuiltins

/// The owner's Family tab: who is in the family, who has been invited, and how
/// many places the plan has left.
///
/// What it guarantees (rules in `FamilyRoster`, which is tested):
/// - Places count invites still waiting to be used, so the owner can't invite
///   two people into one place and have the second refused on their own phone.
/// - Ownership only goes to an active co-caregiver. A receiver made owner
///   stops being checked on, so receivers are never offered.
/// - Removed members are listed apart, can't be opened or removed again, and
///   can be invited again.
/// - An invite nobody used shows as expired instead of disappearing, and any
///   waiting invite can be reopened for its code, QR code and setup guide.
/// - A failed action says which action failed, in words, with Try Again.
///   A re-send that isn't sent says the old link and code no longer work.
/// - Loads can't land out of order.
struct FamilyView: View {
    @EnvironmentObject var appState: AppState
    @State private var family: Family?
    @State private var members: [FamilyMember] = []
    /// Invites nobody has used yet, one per person.
    @State private var openInvites: [PendingInvite] = []
    /// Invites that ran out unused, for people who haven't joined.
    @State private var expiredInvites: [PendingInvite] = []
    /// Every recent invite row, used ones included: a removed member's own
    /// user row is no longer readable (RLS), so their name and number come
    /// from the invite they joined with.
    @State private var inviteRows: [PendingInvite] = []
    @State private var isLoading = false
    @State private var loadError: String?
    /// Drops a slower, older load that finishes after a newer one.
    @State private var loadGeneration = 0

    @State private var inviteRequest: InviteRequest?
    @State private var paywall: PaywallContext?
    /// At the limit on the top plan: nothing to buy, so explain instead.
    @State private var planFullMessage: String?
    @State private var transferTarget: FamilyMember?
    @State private var memberToRemove: FamilyMember?
    @State private var inviteToCancel: PendingInvite?
    @State private var selectedInvite: PendingInvite?
    @State private var actionFailure: ActionFailure?
    @State private var showRemoved = false

    /// Invite (or legacy member row) being re-sent: row spinner, and blocks a
    /// second re-send.
    @State private var resendingId: UUID?
    /// Drives the native Messages composer for a re-send.
    @State private var pendingResendInvite: InviteDetails?
    /// The re-send the composer is showing, for the result that follows.
    @State private var lastResend: InviteDetails?
    /// A re-send that wasn't sent: the old link is already dead, so say so.
    @State private var unsentResend: InviteDetails?
    @State private var toast: String?

    private var isOwner: Bool { appState.currentUserRole == .owner }

    private var currentMembers: [FamilyMember] { FamilyRoster.currentMembers(members) }
    private var removedMembers: [FamilyMember] { FamilyRoster.removedMembers(members) }

    private var receiverUsage: FamilyRoster.SlotUsage {
        FamilyRoster.usage(for: .receiver, members: members, openInvites: openInvites,
                           limit: family?.maxReceivers ?? 1)
    }

    private var viewerUsage: FamilyRoster.SlotUsage {
        FamilyRoster.usage(for: .viewer, members: members, openInvites: openInvites,
                           limit: family?.maxViewers ?? 0)
    }

    var body: some View {
        NavigationStack {
            alerts(sheets(list))
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            if let family {
                planSection(family)
            }

            if let loadError {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await loadData() }
                        } label: {
                            Text("Try Again")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            } else if isLoading && members.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }

            membersSection

            if isOwner && (!openInvites.isEmpty || !expiredInvites.isEmpty) {
                invitesSection
            }

            if isOwner {
                addSection
            }

            // Owner only: a co-caregiver can't read removed members' names or
            // invites, so the group would be a list of "Removed member" rows.
            if isOwner && !removedMembers.isEmpty {
                removedSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(tone: .neutral))
        .navigationTitle("Family")
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(DailyOKColor.green700))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityHidden(true) // announced via UIAccessibility.post
            }
        }
        .refreshable { await loadData() }
        .task { await loadData() }
    }

    private func planSection(_ family: Family) -> some View {
        Section("Family") {
            HStack {
                Text(family.name)
                    .font(.headline)
                Spacer()
                planBadge(family)
            }
        }
    }

    @ViewBuilder
    private func planBadge(_ family: Family) -> some View {
        let state = FamilyRoster.planState(family)
        let plan = family.subscriptionTier.displayName
        let label: String = {
            switch state {
            case .active: return plan
            case .renewSoon: return String(localized: "\(plan) · Payment issue")
            case .endsOn(let date):
                return String(localized: "\(plan) · Ends \(date.formatted(.dateTime.month(.abbreviated).day()))")
            case .expired: return String(localized: "\(plan) · Expired")
            }
        }()
        let needsAttention = state != .active
        let badge = Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(needsAttention ? FamilyTabStyle.warningText : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (needsAttention ? DailyOKColor.warning : DailyOKColor.green500).opacity(0.16),
                in: Capsule()
            )

        if isOwner && needsAttention {
            Button {
                paywall = PaywallContext(message: state == .expired
                    ? String(localized: "Your plan has ended. Renew to keep daily check-ins and alerts running for everyone.")
                    : String(localized: "Keep your plan active so daily check-ins and alerts don't stop."))
            } label: {
                badge
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows plans")
        } else {
            badge
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(currentMembers) { member in
                memberRow(member)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if isOwner && FamilyRoster.canRemove(member) {
                            Button("Remove", role: .destructive) {
                                memberToRemove = member
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if isOwner && member.status == .invited {
                            Button("Re-send") {
                                Task { await resendLegacyInvite(member) }
                            }
                            .tint(.blue)
                            .disabled(resendingId != nil)
                        }
                        if isOwner && FamilyRoster.canTransferOwnership(to: member) {
                            Button {
                                transferTarget = member
                            } label: {
                                Label("Make Owner", systemImage: "crown")
                            }
                            .tint(.orange)
                        }
                    }
                    .contextMenu {
                        memberMenu(member)
                    }
            }
        } header: {
            Text("Members")
        } footer: {
            if isOwner && currentMembers.contains(where: FamilyRoster.canTransferOwnership(to:)) {
                Text("Touch and hold a co-caregiver to make them the owner.")
            }
        }
    }

    /// Only a row that opens something is a link; the others are plain rows
    /// (not dimmed, disabled links).
    @ViewBuilder
    private func memberRow(_ member: FamilyMember) -> some View {
        if FamilyRoster.opensSettings(member, isOwner: isOwner) {
            // Plain push. The iOS 18 zoom transition added a swipe-down / pinch
            // dismiss that skipped ReceiverSettingsView's unsaved-changes
            // prompt, silently dropping schedule edits.
            NavigationLink {
                ReceiverSettingsView(member: member)
            } label: {
                MemberRow(member: member)
            }
            .simultaneousGesture(TapGesture().onEnded { DailyOKHaptics.selection() })
        } else {
            MemberRow(member: member, isYou: isOwner && member.role == .owner)
        }
    }

    @ViewBuilder
    private func memberMenu(_ member: FamilyMember) -> some View {
        if isOwner && FamilyRoster.canTransferOwnership(to: member) {
            Button {
                transferTarget = member
            } label: {
                Label("Make Owner", systemImage: "crown")
            }
        }
        if isOwner && member.status == .invited {
            Button {
                Task { await resendLegacyInvite(member) }
            } label: {
                Label("Re-send Invite", systemImage: "arrow.clockwise")
            }
            .disabled(resendingId != nil)
        }
        if isOwner && FamilyRoster.canRemove(member) {
            Button(role: .destructive) {
                memberToRemove = member
            } label: {
                Label("Remove", systemImage: "person.badge.minus")
            }
        }
    }

    private var invitesSection: some View {
        Section {
            ForEach(openInvites) { invite in
                Button {
                    selectedInvite = invite
                } label: {
                    PendingInviteRow(invite: invite, isBusy: resendingId == invite.id, isExpired: false)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the setup code and QR code")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Cancel Invite", role: .destructive) {
                        inviteToCancel = invite
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Re-send") {
                        Task { await resendPendingInvite(invite) }
                    }
                    .tint(.blue)
                    .disabled(resendingId != nil)
                }
                .contextMenu {
                    Button {
                        Task { await resendPendingInvite(invite) }
                    } label: {
                        Label("Re-send Invite", systemImage: "arrow.clockwise")
                    }
                    .disabled(resendingId != nil)
                    Button(role: .destructive) {
                        inviteToCancel = invite
                    } label: {
                        Label("Cancel Invite", systemImage: "xmark.circle")
                    }
                }
            }

            ForEach(expiredInvites) { invite in
                Button {
                    selectedInvite = invite
                } label: {
                    PendingInviteRow(invite: invite, isBusy: resendingId == invite.id, isExpired: true)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Dismiss", role: .destructive) {
                        Task { await cancelInvite(invite) }
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Send New") {
                        Task { await resendPendingInvite(invite) }
                    }
                    .tint(.blue)
                    .disabled(resendingId != nil)
                }
                .contextMenu {
                    Button {
                        Task { await resendPendingInvite(invite) }
                    } label: {
                        Label("Send a New Invite", systemImage: "arrow.clockwise")
                    }
                    .disabled(resendingId != nil)
                    Button(role: .destructive) {
                        Task { await cancelInvite(invite) }
                    } label: {
                        Label("Remove from List", systemImage: "xmark.circle")
                    }
                }
            }
        } header: {
            Text("Waiting to Join")
        } footer: {
            Text("Tap an invite for its setup code and QR code. A re-sent invite replaces the old link and code.")
        }
    }

    private var addSection: some View {
        Section {
            Button {
                startInvite(.receiver)
            } label: {
                Label(inviteLabel(String(localized: "Invite Someone to Check On"), usage: receiverUsage),
                      systemImage: "person.badge.plus")
            }
            Button {
                startInvite(.viewer)
            } label: {
                Label(inviteLabel(String(localized: "Add a Co-Caregiver"), usage: viewerUsage),
                      systemImage: "person.2")
            }
        } footer: {
            if family != nil {
                Text(usageFooter)
            }
        }
    }

    private func inviteLabel(_ title: String, usage: FamilyRoster.SlotUsage) -> String {
        guard usage.isFull else { return title }
        return family?.subscriptionTier.isTopTier == true
            ? String(localized: "\(title) (plan full)")
            : String(localized: "\(title) (upgrade needed)")
    }

    private var usageFooter: String {
        var receivers = String(localized: "Checking on \(receiverUsage.used) of \(receiverUsage.limit).")
        if receiverUsage.waiting > 0 {
            receivers += " " + String(localized: "\(receiverUsage.waiting) waiting to join.")
        }
        var viewers: String
        if viewerUsage.limit > 0 {
            viewers = String(localized: "Co-caregivers: \(viewerUsage.used) of \(viewerUsage.limit).")
            if viewerUsage.waiting > 0 {
                viewers += " " + String(localized: "\(viewerUsage.waiting) waiting to join.")
            }
        } else {
            viewers = String(localized: "Your plan doesn't include co-caregivers.")
        }
        return receivers + "\n" + viewers
            + "\n" + String(localized: "Co-caregivers are told when a check-in is missed. They're never asked to check in.")
    }

    private var removedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showRemoved) {
                ForEach(removedMembers) { member in
                    let joinedWith = FamilyRoster.joinInvite(for: member, in: inviteRows)
                    let name = FamilyRoster.nonEmpty(member.user?.displayName) ?? FamilyRoster.nonEmpty(joinedWith?.name)
                    let phone = FamilyRoster.nonEmpty(member.user?.phone) ?? FamilyRoster.nonEmpty(joinedWith?.phone)
                    MemberRow(member: member, fallbackName: name)
                        .swipeActions(edge: .leading) {
                            if isOwner, let phone {
                                Button("Invite Again") { reinvite(member, name: name ?? "", phone: phone) }
                                    .tint(.blue)
                            }
                        }
                        .contextMenu {
                            if isOwner, let phone {
                                Button {
                                    reinvite(member, name: name ?? "", phone: phone)
                                } label: {
                                    Label("Invite Again", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                }
            } label: {
                Text("Removed (\(removedMembers.count))")
            }
        } footer: {
            Text("Removed members — including anyone paused when the plan changed — get no check-ins or alerts. Their history is kept.")
        }
    }

    // MARK: - Presentations

    private func sheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $inviteRequest, onDismiss: { Task { await loadData() } }) { request in
                InviteReceiverSheet(
                    role: request.role,
                    initialName: request.name,
                    initialPhone: request.phone,
                    familyId: family?.id
                ) { await loadData() }
                .dailyokGlassSheet(style: .regular)
            }
            .sheet(item: $selectedInvite) { invite in
                InviteDetailSheet(
                    invite: invite,
                    onResend: { afterSheetCloses { await resendPendingInvite(invite) } },
                    onCancel: {
                        afterSheetCloses {
                            if invite.expiresAt <= Date() {
                                await cancelInvite(invite)
                            } else {
                                inviteToCancel = invite
                            }
                        }
                    }
                )
                .dailyokGlassSheet(style: .regular)
            }
            .inviteComposer(item: $pendingResendInvite) { sent in
                handleResendComposerFinish(sent: sent)
            }
            .sheet(item: $paywall, onDismiss: { Task { await loadData() } }) { context in
                // Wrap in a NavigationStack so the paywall has a title bar and an
                // explicit Done button (App Review expects a dismissible paywall).
                NavigationStack {
                    SubscriptionView()
                        .safeAreaInset(edge: .top) {
                            Label(context.message, systemImage: "person.2.fill")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { paywall = nil }
                            }
                        }
                }
            }
    }

    private func alerts<Content: View>(_ content: Content) -> some View {
        content
            .alert(
                "Make \(transferTarget.map(displayName) ?? "them") the owner?",
                isPresented: isPresent($transferTarget),
                presenting: transferTarget
            ) { target in
                Button("Make \(displayName(target)) Owner", role: .destructive) {
                    DailyOKHaptics.warning()
                    Task { await transferOwnership(to: target) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { target in
                let name = displayName(target)
                Text("\(name) will manage the family's check-ins, invites and plan. You'll become a co-caregiver and can't undo this yourself.\n\nYour subscription stays on your Apple ID and keeps paying for this family until you cancel it (Settings › Apple ID › Subscriptions, or Manage Subscription in Daily OK's Settings). \(name) can take the plan over by choosing one of their own.")
            }
            .alert(
                "Cancel Invite",
                isPresented: isPresent($inviteToCancel),
                presenting: inviteToCancel
            ) { invite in
                Button("Cancel Invite", role: .destructive) {
                    Task { await cancelInvite(invite) }
                }
                Button("Keep", role: .cancel) {}
            } message: { invite in
                Text("The link and setup code sent to \(invite.name ?? String(localized: "this person")) will stop working.")
            }
            .alert(
                "Remove \(memberToRemove.map(displayName) ?? "member")?",
                isPresented: isPresent($memberToRemove),
                presenting: memberToRemove
            ) { member in
                Button("Remove \(displayName(member))", role: .destructive) {
                    DailyOKHaptics.warning()
                    Task { await removeMember(member) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { member in
                Text(removeMessage(for: member))
            }
            .alert(
                actionFailure?.title ?? "",
                isPresented: isPresent($actionFailure),
                presenting: actionFailure
            ) { failure in
                if let retry = failure.retry {
                    Button("Try Again") { Task { await retry() } }
                }
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
            .alert(
                "Invite not sent",
                isPresented: isPresent($unsentResend),
                presenting: unsentResend
            ) { details in
                Button("Send Now") {
                    lastResend = details
                    pendingResendInvite = details
                }
                Button("Not Now", role: .cancel) {}
            } message: { details in
                Text("The link and code \(details.name ?? String(localized: "they")) had before no longer work — only the new ones do. Send the new invite now?")
            }
            .alert(
                "Your plan is full",
                isPresented: isPresent($planFullMessage),
                presenting: planFullMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    /// A Bool binding for "this optional is set", clearing it on dismiss.
    private func isPresent<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }

    private func displayName(_ member: FamilyMember) -> String {
        if let name = member.user?.displayName, !name.isEmpty { return name }
        return String(localized: "this member")
    }

    private func removeMessage(for member: FamilyMember) -> String {
        let name = displayName(member)
        switch member.role {
        case .viewer:
            return String(localized: "\(name) will stop getting missed-check-in alerts and lose access to check-ins, history, location and care notes.")
        default:
            return String(localized: "\(name) will stop getting daily check-ins now, and no one will be alerted if they don't respond. Their history is kept, and you can invite them again.")
        }
    }

    /// Present something after the current sheet has finished closing; two
    /// presentations in one update drop the second.
    private func afterSheetCloses(_ action: @escaping @MainActor () async -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            await action()
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { if toast == message { toast = nil } }
        }
    }

    // MARK: - Data

    private func loadData() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        do {
            let fam = try await FamilyService.shared.getFamily()
            guard generation == loadGeneration else { return }
            guard let fam else {
                family = nil
                members = []
                openInvites = []
                expiredInvites = []
                inviteRows = []
                loadError = nil
                isLoading = false
                return
            }
            let loadedMembers = try await FamilyService.shared.getFamilyMembers(familyId: fam.id)
            // Non-fatal: the member list is what matters if this fails.
            var inviteRows: [PendingInvite]?
            if isOwner {
                inviteRows = try? await FamilyService.shared.recentInvites(familyId: fam.id)
            }
            guard generation == loadGeneration else { return }
            family = fam
            members = loadedMembers
            if let inviteRows {
                let parts = FamilyRoster.partitionInvites(inviteRows, members: loadedMembers)
                openInvites = parts.open
                expiredInvites = parts.expired
                self.inviteRows = inviteRows
            }
            loadError = nil
        } catch {
            guard generation == loadGeneration else { return }
            // Keep what is on screen; say the refresh failed.
            loadError = members.isEmpty
                ? String(localized: "Couldn't load your family. Check your connection and try again.")
                : String(localized: "Couldn't refresh. What you see may be out of date.")
        }
        isLoading = false
    }

    // MARK: - Actions

    /// Open the invite sheet, or explain the limit when this kind of place is
    /// full (counting invites still waiting).
    private func startInvite(_ role: UserRole, name: String = "", phone: String = "") {
        let usage = role == .viewer ? viewerUsage : receiverUsage
        if usage.isFull {
            presentLimit(for: role, usage: usage)
            return
        }
        inviteRequest = InviteRequest(role: role, name: name, phone: phone)
    }

    private func reinvite(_ member: FamilyMember, name: String, phone: String) {
        startInvite(member.role == .viewer ? .viewer : .receiver,
                    name: name,
                    phone: phone)
    }

    private func presentLimit(for role: UserRole, usage: FamilyRoster.SlotUsage) {
        let tier = family?.subscriptionTier ?? .free
        let message = FamilyRoster.limitMessage(for: role, usage: usage, tier: tier)
        if tier.isTopTier {
            planFullMessage = message
        } else {
            paywall = PaywallContext(message: message)
        }
    }

    private func removeMember(_ member: FamilyMember) async {
        guard FamilyRoster.canRemove(member) else { return }
        let name = displayName(member)
        do {
            try await FamilyService.shared.removeMember(memberId: member.id)
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "\(name) removed"))
            showToast(String(localized: "\(name) removed"))
        } catch {
            DailyOKHaptics.error()
            actionFailure = ActionFailure(
                title: String(localized: "Couldn't remove \(name)"),
                message: Self.friendly(error),
                retry: { await removeMember(member) }
            )
        }
        // Either way, so the list matches the server.
        await loadData()
    }

    /// Re-send an invite that hasn't been used (or one that expired): the
    /// server creates a fresh link and code and expires the old ones, then the
    /// owner sends the new text.
    private func resendPendingInvite(_ invite: PendingInvite) async {
        guard let family, resendingId == nil else { return }
        let name = invite.name ?? String(localized: "this person")
        guard let phone = invite.phone, !phone.isEmpty else {
            actionFailure = ActionFailure(
                title: String(localized: "Can't re-send to \(name)"),
                message: String(localized: "This invite has no phone number. Cancel it and send a new one."),
                retry: nil
            )
            return
        }
        // An expired invite no longer holds a place, so a new one needs a free place.
        if invite.expiresAt <= Date() {
            let usage = invite.invitedRole == .viewer ? viewerUsage : receiverUsage
            if usage.isFull {
                presentLimit(for: invite.invitedRole, usage: usage)
                return
            }
        }

        resendingId = invite.id
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Preparing a new invite for \(name)"))
        defer { resendingId = nil }
        do {
            let details = try await FamilyService.shared.inviteReceiver(
                familyId: family.id,
                name: invite.name ?? "Family Member",
                phone: phone,
                checkinTime: String((invite.checkinTime ?? "08:00").prefix(5)),
                role: invite.invitedRole
            )
            lastResend = details
            pendingResendInvite = details
            await loadData()
        } catch {
            DailyOKHaptics.error()
            actionFailure = ActionFailure(
                title: String(localized: "Couldn't re-send to \(name)"),
                message: Self.friendly(error),
                retry: { await resendPendingInvite(invite) }
            )
        }
    }

    /// Legacy: a family_members row still in "invited" status (from before
    /// invites lived only in invite_tokens).
    private func resendLegacyInvite(_ member: FamilyMember) async {
        guard let family, member.status == .invited, resendingId == nil else { return }
        let name = displayName(member)
        guard let phone = member.user?.phone, !phone.isEmpty else {
            actionFailure = ActionFailure(
                title: String(localized: "Can't re-send to \(name)"),
                message: String(localized: "There's no phone number for \(name). Remove them and send a new invite."),
                retry: nil
            )
            return
        }
        resendingId = member.id
        defer { resendingId = nil }

        // Preserve the receiver's configured check-in time instead of silently
        // resetting it to a hardcoded 08:00 on every re-send.
        let checkinTime = await currentCheckinTime(for: member)
        do {
            let invite = try await FamilyService.shared.inviteReceiver(
                familyId: family.id,
                name: member.user?.displayName ?? "Family Member",
                phone: phone,
                checkinTime: checkinTime,
                role: member.role == .viewer ? .viewer : .receiver
            )
            lastResend = invite
            pendingResendInvite = invite
        } catch {
            DailyOKHaptics.error()
            actionFailure = ActionFailure(
                title: String(localized: "Couldn't re-send to \(name)"),
                message: Self.friendly(error),
                retry: { await resendLegacyInvite(member) }
            )
        }
    }

    private func cancelInvite(_ invite: PendingInvite) async {
        do {
            try await FamilyService.shared.cancelInvite(id: invite.id)
            DailyOKHaptics.success()
        } catch {
            DailyOKHaptics.error()
            actionFailure = ActionFailure(
                title: String(localized: "Couldn't cancel the invite"),
                message: Self.friendly(error),
                retry: { await cancelInvite(invite) }
            )
        }
        await loadData()
    }

    /// Called when the re-send composer closes. Re-sending already replaced
    /// the old link and code server-side, so "not sent" must say that.
    private func handleResendComposerFinish(sent: Bool) {
        let details = lastResend
        lastResend = nil
        guard sent else {
            if let details {
                afterSheetCloses { unsentResend = details }
            }
            return
        }
        let name = details?.name ?? String(localized: "them")
        DailyOKHaptics.success()
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Invite re-sent to \(name)"))
        showToast(String(localized: "Invite re-sent to \(name)"))
    }

    /// The receiver's current check-in time as "HH:mm", read from their
    /// receiver_settings row. Falls back to "08:00" only if it can't be read.
    private func currentCheckinTime(for member: FamilyMember) async -> String {
        struct Row: Decodable { let checkin_time: String? }
        let rows: [Row]? = try? await SupabaseService.shared.client
            .from("receiver_settings")
            .select("checkin_time")
            .eq("family_member_id", value: member.id.uuidString)
            .limit(1)
            .execute()
            .value
        if let t = rows?.first?.checkin_time, t.count >= 5 {
            return String(t.prefix(5)) // "HH:mm:ss" -> "HH:mm"
        }
        return "08:00"
    }

    private func transferOwnership(to member: FamilyMember) async {
        guard let family, FamilyRoster.canTransferOwnership(to: member) else { return }
        let name = displayName(member)
        do {
            // transfer_family_ownership_v2 (00058): one transaction, only the
            // current owner, only to an active co-caregiver.
            try await FamilyService.shared.transferOwnership(familyId: family.id, to: member.userId)
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "\(name) is now the owner"))
            // Reflect the demotion immediately so ContentView swaps OwnerTabView
            // for ViewerTabView instead of leaving stale owner-only controls up.
            appState.currentUserRole = .viewer
        } catch {
            DailyOKHaptics.error()
            actionFailure = ActionFailure(
                title: String(localized: "Couldn't make \(name) the owner"),
                message: Self.friendly(error),
                retry: { await transferOwnership(to: member) }
            )
            await loadData()
        }
    }

    /// Words for a failed action. The raw text ("Network error: new row
    /// violates…") read like a connection problem even when it wasn't.
    private static func friendly(_ error: Error) -> String {
        if let http = error as? EdgeFunctionsClient.HTTPError, let message = http.serverMessage {
            return message
        }
        if let familyError = error as? FamilyError, let message = familyError.errorDescription {
            return message
        }
        if error is URLError {
            return String(localized: "Check your internet connection and try again.")
        }
        let text = "\(error)"
        if text.contains("co-caregiver (viewer)") {
            return String(localized: "Only a co-caregiver can become the owner.")
        }
        if text.contains("must be an active member") {
            return String(localized: "They're no longer an active member of this family. Pull down to refresh.")
        }
        if text.contains("Only the current owner") {
            return String(localized: "Only the family's owner can do that. Pull down to refresh.")
        }
        if text.contains("Roles change only") || text.contains("rejoins through a new invite") {
            return String(localized: "That change needs a new invite.")
        }
        return String(localized: "Something went wrong. Check your connection and try again.")
    }
}

/// Which invite sheet to open, and what to prefill.
private struct InviteRequest: Identifiable {
    let id = UUID()
    let role: UserRole
    var name: String = ""
    var phone: String = ""
}

/// Why the paywall is showing.
private struct PaywallContext: Identifiable {
    let id = UUID()
    let message: String
}

/// A failed action, named, with an optional retry of that same action.
private struct ActionFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let retry: (@MainActor () async -> Void)?
}

enum FamilyTabStyle {
    /// Orange that stays readable as text (systemOrange on white is ~2.2:1).
    static let warningText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? .systemOrange
            : UIColor(red: 0.62, green: 0.33, blue: 0.0, alpha: 1)
    })
}

struct MemberRow: View {
    let member: FamilyMember
    var isYou: Bool = false
    /// Used when the user row can't be read (a removed member): the name
    /// from the invite they joined with.
    var fallbackName: String? = nil

    private var name: String {
        if let name = member.user?.displayName, !name.isEmpty {
            return isYou ? String(localized: "\(name) (you)") : name
        }
        if let fallbackName, !fallbackName.isEmpty { return fallbackName }
        // A removed member's user row is no longer readable (RLS).
        return member.status == .deactivated
            ? String(localized: "Removed member")
            : String(localized: "Invited")
    }

    private var roleText: String {
        switch member.role {
        case .owner: return String(localized: "Owner")
        case .receiver: return String(localized: "Checks in daily")
        case .viewer: return String(localized: "Co-caregiver")
        }
    }

    private var roleIcon: String {
        switch member.role {
        case .owner: return "crown"
        case .receiver: return "heart"
        case .viewer: return "person.2"
        }
    }

    private var detail: String {
        if member.status == .active, member.role != .owner, let joined = member.joinedAt {
            return String(localized: "\(roleText) · joined \(joined.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return roleText
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: roleIcon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch member.status {
            case .invited:
                Label("Invited", systemImage: "envelope")
                    .font(.caption)
                    .foregroundStyle(FamilyTabStyle.warningText)
            case .deactivated:
                Text("Removed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            case .active:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A sent invite nobody has used yet, or one that ran out unused.
private struct PendingInviteRow: View {
    let invite: PendingInvite
    let isBusy: Bool
    let isExpired: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isExpired ? "clock.badge.exclamationmark" : "envelope.badge")
                .foregroundStyle(isExpired ? FamilyTabStyle.warningText : Color.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(invite.name ?? String(localized: "Invited"))
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(isExpired ? FamilyTabStyle.warningText : Color.secondary)
            }

            Spacer()

            if isBusy {
                ProgressView()
                    .accessibilityLabel("Preparing a new invite")
            } else if !isExpired, let code = invite.pairingCode {
                Text(code)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Setup code \(code.map(String.init).joined(separator: " "))")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if invite.invitedRole == .viewer { parts.append(String(localized: "Co-caregiver")) }
        if isExpired {
            let name = invite.name ?? String(localized: "They")
            parts.append(String(localized: "Invite expired — \(name) hasn't joined"))
        } else {
            if let phone = invite.phone, !phone.isEmpty { parts.append(phone) }
            parts.append(FamilyRoster.expiryText(expiresAt: invite.expiresAt))
        }
        return parts.joined(separator: " · ")
    }
}

/// A waiting (or expired) invite reopened: the code, QR code and setup guide
/// for when the owner is helping in person or on the phone.
private struct InviteDetailSheet: View {
    let invite: PendingInvite
    let onResend: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showSetupGuide = false

    private var name: String { invite.name ?? String(localized: "them") }
    private var isExpired: Bool { invite.expiresAt <= Date() }

    private var statusLine: String {
        if isExpired {
            return String(localized: "Expired \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted)). \(name) hasn't joined.")
        }
        return String(localized: "Sent \(invite.createdAt.formatted(.relative(presentation: .named))) · \(FamilyRoster.expiryText(expiresAt: invite.expiresAt))")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(invite.invitedRole == .viewer
                             ? String(localized: "Co-caregiver invite")
                             : String(localized: "Invite to check in daily"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let phone = invite.phone, !phone.isEmpty {
                            Text(phone)
                        }
                        Text(statusLine)
                            .font(.subheadline)
                            .foregroundStyle(isExpired ? FamilyTabStyle.warningText : Color.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if !isExpired {
                    InviteHandoffSection(
                        code: invite.pairingCode,
                        link: invite.inviteLink,
                        shareText: FamilyRoster.shareMessage(
                            name: invite.name,
                            role: invite.invitedRole,
                            link: invite.inviteLink,
                            code: invite.pairingCode
                        )
                    )

                    if invite.invitedRole == .receiver {
                        Section {
                            Button {
                                showSetupGuide = true
                            } label: {
                                Label("Setup Guide for \(name)", systemImage: "list.number")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        onResend()
                    } label: {
                        Label(isExpired ? "Send a New Invite" : "Re-send Invite", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        dismiss()
                        onCancel()
                    } label: {
                        Label(isExpired ? "Remove from List" : "Cancel Invite", systemImage: "xmark.circle")
                    }
                } footer: {
                    Text(isExpired
                         ? "A new invite has a new link and setup code."
                         : "Re-sending replaces this link and code with new ones.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tone: .calm))
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSetupGuide) {
                ReceiverSetupGuideView(receiverName: name, pairingCode: invite.pairingCode)
                    .dailyokGlassSheet(style: .thick)
            }
        }
    }
}

// MARK: - Invite Sheet with Setup Guide

struct InviteReceiverSheet: View {
    /// `.receiver` (someone to check on) or `.viewer` (a co-caregiver).
    let role: UserRole
    /// Resolved by the caller; looked up here only if missing.
    let familyId: UUID?
    let onComplete: () async -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name: String
    @State private var phone: String
    /// 9:00 AM, not "now": an invite written at 11:42 PM used to schedule
    /// daily check-ins for 11:42 PM.
    @State private var checkinTime = InviteReceiverSheet.defaultCheckinTime
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var inviteSent = false
    @State private var showSetupGuide = false
    /// Drives the native Messages composer once the invite record exists.
    @State private var pendingInvite: InviteDetails?
    /// The invite that was sent, kept for the code / QR / share shown after.
    @State private var sentInvite: InviteDetails?
    /// Created server-side but the text hasn't gone out. Send Invite reuses
    /// it (a second invite would expire this one), and leaving asks whether
    /// to keep or withdraw it.
    @State private var createdInvite: InviteDetails?
    @State private var showLeaveConfirm = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, phone }

    init(
        role: UserRole = .receiver,
        initialName: String = "",
        initialPhone: String = "",
        familyId: UUID? = nil,
        onComplete: @escaping () async -> Void
    ) {
        self.role = role
        self.familyId = familyId
        self.onComplete = onComplete
        _name = State(initialValue: initialName)
        _phone = State(initialValue: initialPhone)
    }

    static var defaultCheckinTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private var isCaregiver: Bool { role == .viewer }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Mirror OnboardingViewModel.canInviteReceiver: require a non-empty trimmed
    /// name and a plausible (>=10-digit) phone so we don't fire an SMS to garbage
    /// like "abc"/"5" (US-IOS104).
    private var canSendInvite: Bool {
        !trimmedName.isEmpty
            && phone.filter(\.isNumber).count >= 10
            && !isLoading
    }

    private var hasTypedInput: Bool {
        !trimmedName.isEmpty || !phone.filter(\.isNumber).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if !inviteSent {
                    formSections
                } else {
                    sentSections
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tone: .calm))
            .navigationTitle(inviteSent
                             ? String(localized: "Invite Sent")
                             : (isCaregiver ? String(localized: "Add a Co-Caregiver") : String(localized: "Invite Someone")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if inviteSent {
                        Button("Done") { dismiss() }
                    } else {
                        Button("Cancel") { leave() }
                            .disabled(isLoading)
                    }
                }
                if !inviteSent {
                    ToolbarItem(placement: .confirmationAction) {
                        if isLoading {
                            ProgressView()
                                .accessibilityLabel("Creating invite")
                        } else {
                            Button("Send Invite") {
                                Task { await sendInvite() }
                            }
                            .disabled(!canSendInvite)
                        }
                    }
                }
            }
            // Typed details, an invite in flight or an unsent invite are
            // never dropped by a stray swipe.
            .interactiveDismissDisabled(!inviteSent && (isLoading || hasTypedInput || createdInvite != nil))
            .confirmationDialog(
                createdInvite != nil
                    ? String(localized: "This invite hasn't been sent")
                    : String(localized: "Discard this invite?"),
                isPresented: $showLeaveConfirm,
                titleVisibility: .visible
            ) {
                if let created = createdInvite {
                    Button("Keep Invite for Later") { dismiss() }
                    Button("Withdraw Invite", role: .destructive) {
                        Task {
                            if let token = created.token {
                                try? await FamilyService.shared.cancelInvite(token: token)
                            }
                            await onComplete()
                            dismiss()
                        }
                    }
                } else {
                    Button("Discard", role: .destructive) { dismiss() }
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                if createdInvite != nil {
                    Text("Keep it to send later from the Family tab (it holds a place until it's used or cancelled), or withdraw it.")
                }
            }
            .sheet(isPresented: $showSetupGuide) {
                ReceiverSetupGuideView(receiverName: trimmedName, pairingCode: sentInvite?.pairingCode)
                    .dailyokGlassSheet(style: .thick)
            }
            .inviteComposer(item: $pendingInvite) { sent in
                if sent {
                    errorMessage = nil
                    createdInvite = nil
                    DailyOKHaptics.success()
                    inviteSent = true
                } else {
                    errorMessage = String(localized: "Message not sent. Tap Send Invite to try again — the same link and code will be used.")
                }
            }
        }
    }

    @ViewBuilder
    private var formSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("How It Works", systemImage: "info.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(DailyOKColor.green700)

                if isCaregiver {
                    InstructionRow(number: 1, text: "Enter their name and phone number below")
                    InstructionRow(number: 2, text: "Your Messages app opens with a ready-to-send text — you tap send")
                    InstructionRow(number: 3, text: "They get the app, sign in, and tap the link again (or enter the setup code from the text)")
                    InstructionRow(number: 4, text: "They're told whenever a check-in is missed, and can see check-ins, history and care notes. They're never asked to check in")
                } else {
                    InstructionRow(number: 1, text: "Enter their name and phone number below")
                    InstructionRow(number: 2, text: "Your Messages app opens with a ready-to-send text — you tap send")
                    InstructionRow(number: 3, text: "They tap the link, get the app, and sign in with Apple or an email")
                    InstructionRow(number: 4, text: "They tap the link again, or enter the setup code from the text, and see your family before they join")
                }
            }
            .padding(.vertical, 4)
        }

        Section {
            TextField("Name", text: $name)
                .textContentType(.name)
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .phone }

            TextField("Phone Number", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .focused($focusedField, equals: .phone)
        } header: {
            Text(isCaregiver ? "Co-Caregiver" : "Who You're Checking On")
        } footer: {
            Text("Your Messages app sends the invite to this number, and the family can call or text them from Daily OK.")
        }

        if !isCaregiver {
            Section {
                DatePicker("Daily Check-In Time", selection: $checkinTime, displayedComponents: .hourAndMinute)
            } header: {
                Text("Check-In Schedule")
            } footer: {
                Text("In their own time zone, set when they join. You can change the schedule later (weekdays, weekends, pauses and more) from their settings.")
            }
        }

        Section {
            Text("Tapping Send Invite opens your Messages app with a prewritten text to this person — it's sent from your own phone number, and you choose whether to send it. Standard message rates may apply. See our Privacy Policy (dailyok.net/privacy) and Terms of Use (dailyok.net/terms).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let error = errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DailyOKColor.error)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var sentSections: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(DailyOKColor.green600)
                    .accessibilityHidden(true)

                Text("Invite Sent to \(trimmedName)")
                    .font(.headline)

                Text("When \(trimmedName) signs in and taps the link (or enters the setup code), they'll see your family and can join.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }

        if let sentInvite {
            InviteHandoffSection(code: sentInvite.pairingCode, link: sentInvite.inviteLink, shareText: sentInvite.message)
        }

        if !isCaregiver {
            Section {
                Button {
                    showSetupGuide = true
                } label: {
                    Label("Setup Guide for \(trimmedName)", systemImage: "list.number")
                }
            } footer: {
                Text("Step-by-step help you can go through with \(trimmedName) or send to them.")
            }
        }

        Section("What's Next") {
            VStack(alignment: .leading, spacing: 8) {
                NextStepRow(icon: "clock", text: "Until they join, they're under Waiting to Join in your Family tab — tap them there for the code and QR code")
                if isCaregiver {
                    NextStepRow(icon: "bell.badge", text: "Once they join, they're alerted along with you when a check-in is missed")
                } else {
                    NextStepRow(icon: "gearshape", text: "Once they join, tap their name to change the schedule, alerts and more")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func leave() {
        guard !isLoading else { return }
        if createdInvite != nil || hasTypedInput {
            showLeaveConfirm = true
        } else {
            dismiss()
        }
    }

    private func sendInvite() async {
        // Set before any await: a second tap during the round-trip used to
        // create a second invite, and each one expired the other.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // The composer was cancelled and nothing changed: send the same invite
        // again rather than replacing it.
        if let existing = createdInvite, existing.phone == phone, existing.name == trimmedName {
            pendingInvite = existing
            return
        }
        // The name or number was changed after an unsent invite was created.
        // A re-send only replaces an invite to the SAME number, so withdraw
        // the unsent one first or it would sit there holding a place.
        if let stale = createdInvite, let token = stale.token {
            try? await FamilyService.shared.cancelInvite(token: token)
            createdInvite = nil
        }

        var resolvedFamilyId = familyId
        if resolvedFamilyId == nil {
            resolvedFamilyId = try? await FamilyService.shared.getFamily()?.id
        }
        guard let familyId = resolvedFamilyId else {
            errorMessage = String(localized: "Couldn't find your family. Check your connection and try again.")
            return
        }

        // Wire format for the backend — POSIX-locked to keep the 24h "HH:mm"
        // contract stable across user locales (US-IOS044).
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        do {
            // Create the invite record, then present the native composer so the
            // owner sends the text from their own number. The success state is
            // shown only after the composer reports a real send.
            let invite = try await FamilyService.shared.inviteReceiver(
                familyId: familyId,
                name: trimmedName,
                phone: phone,
                checkinTime: formatter.string(from: checkinTime),
                role: role
            )
            createdInvite = invite
            sentInvite = invite
            pendingInvite = invite
            await onComplete()
        } catch {
            DailyOKHaptics.error()
            errorMessage = edgeErrorMessage(
                error,
                fallback: (error as? FamilyError)?.errorDescription
                    ?? String(localized: "Couldn't create the invite. Check your connection and try again.")
            )
        }
    }
}

/// The setup code, a QR code of the link (for when the owner is with them in
/// person), and a way to send it by other means.
private struct InviteHandoffSection: View {
    let code: String?
    let link: String?
    let shareText: String

    var body: some View {
        Section {
            if let code {
                HStack {
                    Text("Setup code")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(code)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Setup code \(code.map(String.init).joined(separator: " "))")
            }

            if let link, let qr = QRCode.image(for: link) {
                VStack(spacing: 8) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .accessibilityLabel("QR code for the invite link")
                    Text("With them now? They can scan this with their phone's camera.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            ShareLink(item: shareText) {
                Label("Send the invite another way", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Other ways to connect")
        }
    }
}

enum QRCode {
    /// A crisp QR code for `string`, or nil if it can't be generated.
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Helper Views

private struct InstructionRow: View {
    let number: Int
    let text: String

    /// Scales with Dynamic Type so the number never truncates.
    @ScaledMetric(relativeTo: .caption) private var numberWidth: CGFloat = 16

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(DailyOKColor.green700)
                .frame(minWidth: numberWidth, alignment: .trailing)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NextStepRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(DailyOKColor.green700)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
