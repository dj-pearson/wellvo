import SwiftUI
import CoreImage.CIFilterBuiltins

struct FamilyView: View {
    @State private var family: Family?
    @State private var members: [FamilyMember] = []
    @State private var showInviteSheet = false
    @State private var isLoading = false
    @State private var showTransferAlert = false
    @State private var transferTarget: FamilyMember?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let family {
                    Section("Family") {
                        HStack {
                            Text(family.name)
                                .font(.headline)
                            Spacer()
                            Text(family.subscriptionTier.rawValue.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                }

                Section("Members") {
                    ForEach(members) { member in
                        NavigationLink {
                            if member.role == .receiver {
                                ReceiverSettingsView(member: member)
                            }
                        } label: {
                            MemberRow(member: member)
                        }
                        .disabled(member.role != .receiver)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if member.role != .owner {
                                Button("Remove", role: .destructive) {
                                    Task { await removeMember(member) }
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if member.status == .invited {
                                Button("Re-send") {
                                    Task { await resendInvite(member) }
                                }
                                .tint(.blue)
                            }
                        }
                        .contextMenu {
                            if member.role != .owner && member.status == .active {
                                Button {
                                    transferTarget = member
                                    showTransferAlert = true
                                } label: {
                                    Label("Transfer Ownership", systemImage: "arrow.right.arrow.left")
                                }
                            }
                            if member.status == .invited {
                                Button {
                                    Task { await resendInvite(member) }
                                } label: {
                                    Label("Re-send Invite", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showInviteSheet = true
                    } label: {
                        Label("Invite Family Member", systemImage: "person.badge.plus")
                    }
                }
            }
            .navigationTitle("Family")
            .refreshable { await loadData() }
            .task { await loadData() }
            .sheet(isPresented: $showInviteSheet) {
                InviteReceiverSheet { await loadData() }
            }
            .alert("Transfer Ownership", isPresented: $showTransferAlert) {
                Button("Transfer", role: .destructive) {
                    if let target = transferTarget {
                        Task { await transferOwnership(to: target) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to transfer ownership to \(transferTarget?.user?.displayName ?? "this member")? You will become a Viewer and lose control of settings and billing.")
            }
        }
    }

    private func loadData() async {
        isLoading = true
        family = try? await FamilyService.shared.getFamily()
        if let family {
            members = (try? await FamilyService.shared.getFamilyMembers(familyId: family.id)) ?? []
        }
        isLoading = false
    }

    private func removeMember(_ member: FamilyMember) async {
        guard member.role != .owner else { return }
        try? await FamilyService.shared.removeMember(memberId: member.id)
        await loadData()
    }

    private func resendInvite(_ member: FamilyMember) async {
        guard let family, member.status == .invited else { return }
        // Re-invite with same details
        try? await FamilyService.shared.inviteReceiver(
            familyId: family.id,
            name: member.user?.displayName ?? "Family Member",
            phone: member.user?.phone ?? "",
            checkinTime: "08:00"
        )
    }

    private func transferOwnership(to member: FamilyMember) async {
        guard let family else { return }
        do {
            // Update family owner
            try await SupabaseService.shared.client
                .from("families")
                .update(["owner_id": member.userId.uuidString])
                .eq("id", value: family.id.uuidString)
                .execute()

            // Update member roles
            try await SupabaseService.shared.client
                .from("family_members")
                .update(["role": "owner"])
                .eq("id", value: member.id.uuidString)
                .execute()

            // Demote current owner to viewer
            if let session = try? await SupabaseService.shared.client.auth.session {
                try await SupabaseService.shared.client
                    .from("family_members")
                    .update(["role": "viewer"])
                    .eq("family_id", value: family.id.uuidString)
                    .eq("user_id", value: session.user.id.uuidString)
                    .execute()
            }

            await loadData()
        } catch {
            errorMessage = WellvoError.network(error).localizedDescription
        }
    }
}

struct MemberRow: View {
    let member: FamilyMember

    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Image(systemName: statusIcon)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.user?.displayName ?? "Invited")
                    .font(.body)

                HStack(spacing: 4) {
                    Text(member.role.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if member.role == .receiver {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }
            }

            Spacer()

            if member.status == .invited {
                Label("Invited", systemImage: "envelope")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.caption2)
                    Text(member.status.rawValue.capitalized)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .cornerRadius(8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.user?.displayName ?? "Invited"), \(member.role.rawValue), status: \(statusLabel)")
    }

    private var statusColor: Color {
        switch member.status {
        case .active: return .green
        case .invited: return .orange
        case .deactivated: return .gray
        }
    }

    private var statusIcon: String {
        switch member.status {
        case .active: return "checkmark"
        case .invited: return "clock"
        case .deactivated: return "xmark"
        }
    }

    private var statusLabel: String {
        switch member.status {
        case .active: return "Active"
        case .invited: return "Invited"
        case .deactivated: return "Deactivated"
        }
    }
}

// MARK: - Invite Sheet with Setup Guide

struct InviteReceiverSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var checkinTime = Date()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var inviteSent = false
    @State private var showSetupGuide = false

    let onComplete: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                if !inviteSent {
                    // How It Works
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("How It Works", systemImage: "info.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)

                            InstructionRow(number: 1, text: "Enter their name and phone number below")
                            InstructionRow(number: 2, text: "They'll receive a text with an App Store link")
                            InstructionRow(number: 3, text: "They download the app and sign in with that same phone number")
                            InstructionRow(number: 4, text: "The app automatically connects them — no codes needed")
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        TextField("Name", text: $name)
                            .textContentType(.name)

                        TextField("Phone Number", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                    } header: {
                        Text("Receiver Details")
                    } footer: {
                        Text("Use the phone number they'll sign into the app with. This is how they're automatically matched to your family.")
                    }

                    Section {
                        DatePicker("Daily Check-In Time", selection: $checkinTime, displayedComponents: .hourAndMinute)
                    } header: {
                        Text("Check-In Schedule")
                    } footer: {
                        Text("You can customize the schedule later (weekday/weekend, per-day, pause, etc.) from their settings.")
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                } else {
                    // Success state with setup guide preview
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.green)

                            Text("Invite Sent to \(name)!")
                                .font(.headline)

                            Text("A text message has been sent to \(phone) with instructions to download and set up the app.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }

                    Section {
                        Button {
                            showSetupGuide = true
                        } label: {
                            HStack {
                                Image(systemName: "list.number")
                                Text("View Setup Guide for \(name)")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("Share these instructions with \(name) if they need help getting set up.")
                    }

                    Section("What's Next") {
                        VStack(alignment: .leading, spacing: 8) {
                            NextStepRow(icon: "clock", text: "Once they sign in, they'll appear in your Family tab")
                            NextStepRow(icon: "gearshape", text: "Tap their name to customize schedule, escalation, and more")
                            NextStepRow(icon: "bell.badge", text: "You can send a manual check-in anytime from their settings")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(inviteSent ? "Invite Sent" : "Invite Receiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !inviteSent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send Invite") {
                            Task { await sendInvite() }
                        }
                        .disabled(name.isEmpty || phone.isEmpty || isLoading)
                    }
                }
            }
            .sheet(isPresented: $showSetupGuide) {
                ReceiverSetupGuideView(receiverName: name)
            }
        }
    }

    private func sendInvite() async {
        guard let family = try? await FamilyService.shared.getFamily() else {
            errorMessage = "Family not found"
            return
        }

        isLoading = true
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        do {
            try await FamilyService.shared.inviteReceiver(
                familyId: family.id,
                name: name,
                phone: phone,
                checkinTime: formatter.string(from: checkinTime)
            )
            await onComplete()
            inviteSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Helper Views

private struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.green)
                .frame(width: 16, alignment: .trailing)

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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.green)
                .frame(width: 20)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
