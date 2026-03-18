import SwiftUI

struct HistoryView: View {
    @State private var selectedReceiver: FamilyMember?
    @State private var checkIns: [CheckIn] = []
    @State private var members: [FamilyMember] = []
    @State private var isLoading = false
    @State private var selectedDays = 30

    var body: some View {
        NavigationStack {
            VStack {
                // Time range picker
                Picker("Period", selection: $selectedDays) {
                    Text("7 Days").tag(7)
                    Text("30 Days").tag(30)
                    Text("90 Days").tag(90)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Receiver selector
                if !members.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(members) { member in
                                Button {
                                    selectedReceiver = member
                                    Task { await loadHistory() }
                                } label: {
                                    Text(member.user?.displayName ?? "Unknown")
                                        .font(.subheadline)
                                        .fontWeight(selectedReceiver?.id == member.id ? .bold : .regular)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedReceiver?.id == member.id ? Color.green : Color(.tertiarySystemFill)
                                        )
                                        .foregroundStyle(selectedReceiver?.id == member.id ? .white : .primary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if checkIns.isEmpty {
                    Spacer()
                    Text("No check-in history")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    // Check-in list
                    List(checkIns) { checkIn in
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(checkIn.checkedInAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.body)

                                HStack(spacing: 8) {
                                    Text(checkIn.source.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let mood = checkIn.mood {
                                        Text(moodEmoji(mood))
                                    }
                                }
                            }

                            Spacer()
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .task { await loadMembers() }
            .onChange(of: selectedDays) { _ in
                Task { await loadHistory() }
            }
        }
    }

    private func loadMembers() async {
        guard let family = try? await FamilyService.shared.getFamily() else { return }
        let allMembers = try? await FamilyService.shared.getFamilyMembers(familyId: family.id)
        members = allMembers?.filter { $0.role == .receiver && $0.status == .active } ?? []
        if selectedReceiver == nil { selectedReceiver = members.first }
        await loadHistory()
    }

    private func loadHistory() async {
        guard let receiver = selectedReceiver,
              let family = try? await FamilyService.shared.getFamily() else { return }
        isLoading = true
        checkIns = (try? await CheckInService.shared.checkInHistory(
            receiverId: receiver.userId,
            familyId: family.id,
            days: selectedDays
        )) ?? []
        isLoading = false
    }

    private func moodEmoji(_ mood: Mood) -> String {
        switch mood {
        case .happy: return "😊"
        case .neutral: return "😐"
        case .tired: return "😴"
        }
    }
}
