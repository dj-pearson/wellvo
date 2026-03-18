import SwiftUI

struct FamilyView: View {
    @State private var family: Family?
    @State private var members: [FamilyMember] = []
    @State private var showInviteSheet = false
    @State private var isLoading = false

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
                        MemberRow(member: member)
                    }
                    .onDelete { indexSet in
                        Task { await removeMember(at: indexSet) }
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

    private func removeMember(at offsets: IndexSet) async {
        for index in offsets {
            let member = members[index]
            guard member.role != .owner else { continue }
            try? await FamilyService.shared.removeMember(memberId: member.id)
        }
        await loadData()
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

                Text(member.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(member.status.rawValue.capitalized)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .cornerRadius(8)
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

struct InviteReceiverSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var checkinTime = Date()
    @State private var isLoading = false
    @State private var errorMessage: String?

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
            }
            .navigationTitle("Invite Receiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Invite") {
                        Task { await sendInvite() }
                    }
                    .disabled(name.isEmpty || phone.isEmpty || isLoading)
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
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
