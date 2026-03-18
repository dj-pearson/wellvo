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
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

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
                Text(member.status.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(8)
            }
        }
    }

    private var statusColor: Color {
        switch member.status {
        case .active: return .green
        case .invited: return .orange
        case .deactivated: return .gray
        }
    }
}

// MARK: - Invite Sheet with QR Code

struct InviteReceiverSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var checkinTime = Date()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var generatedInviteLink: String?
    @State private var showQRCode = false

    let onComplete: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Receiver Details") {
                    TextField("Name", text: $name)
                        .textContentType(.name)

                    TextField("Phone Number", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                Section("Check-In Schedule") {
                    DatePicker("Daily Check-In Time", selection: $checkinTime, displayedComponents: .hourAndMinute)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // QR Code section (shown after invite is created)
                if let link = generatedInviteLink {
                    Section("Share Invite") {
                        VStack(spacing: 12) {
                            if let qrImage = generateQRCode(from: link) {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200)
                                    .padding()
                            }

                            Text("Scan this QR code or share the link:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ShareLink(item: link) {
                                Label("Share Invite Link", systemImage: "square.and.arrow.up")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Invite Receiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if generatedInviteLink == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send Invite") {
                            Task { await sendInvite() }
                        }
                        .disabled(name.isEmpty || phone.isEmpty || isLoading)
                    }
                }
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

            // Generate invite link for QR code display
            // In production this comes from the edge function response
            generatedInviteLink = "https://wellvo.net/invite?phone=\(phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? phone)"
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for clarity
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
