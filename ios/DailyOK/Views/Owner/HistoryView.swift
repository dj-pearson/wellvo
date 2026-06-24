import SwiftUI

struct HistoryView: View {
    @State private var selectedReceiver: FamilyMember?
    @State private var checkIns: [CheckIn] = []
    @State private var members: [FamilyMember] = []
    @State private var isLoading = false
    @State private var selectedDays = 30
    @State private var receiverSettings: ReceiverSettings?
    @State private var showPDFShare = false
    @State private var pdfData: Data?

    /// Calendar weekday numbers (1=Sun…7=Sat) the selected receiver is scheduled
    /// to check in on, so the heatmap doesn't paint unscheduled/paused days as
    /// "missed". Nil → treat every day as scheduled (legacy behavior).
    private var scheduledWeekdays: Set<Int>? {
        guard let settings = receiverSettings else { return nil }
        if settings.schedulePaused { return [] }
        switch settings.scheduleType {
        case .daily, .weekdayWeekend:
            return [1, 2, 3, 4, 5, 6, 7]
        case .custom:
            guard let custom = settings.customSchedule else { return nil }
            let keyToWeekday: [String: Int] = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
            var set = Set<Int>()
            for (key, weekday) in keyToWeekday where !custom.times(forDayKey: key).isEmpty {
                set.insert(weekday)
            }
            return set
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Time range picker
                    Picker("Period", selection: $selectedDays) {
                        Text("7 Days").tag(7)
                        Text("30 Days").tag(30)
                        Text("90 Days").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .accessibilityLabel("History time period")

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
                                                Group {
                                                    if selectedReceiver?.id == member.id {
                                                        Capsule()
                                                            .fill(LinearGradient(colors: [DailyOKColor.green500, DailyOKColor.green600], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    } else {
                                                        Capsule().fill(.thinMaterial)
                                                    }
                                                }
                                            )
                                            .foregroundStyle(selectedReceiver?.id == member.id ? .white : .primary)
                                    }
                                    .buttonStyle(.pressable)
                                    .accessibilityLabel("View history for \(member.user?.displayName ?? "Unknown")")
                                    .accessibilityAddTraits(selectedReceiver?.id == member.id ? .isSelected : [])
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if isLoading {
                        HistorySkeletonView()
                    } else if checkIns.isEmpty {
                        EmptyStateView(
                            systemImage: "calendar.badge.exclamationmark",
                            title: "No check-in history",
                            message: "Once your family starts checking in, their history will show up here."
                        )
                        .padding(.top, 20)
                    } else {
                        // Calendar Heatmap
                        CalendarHeatmapView(
                            checkIns: checkIns,
                            days: selectedDays,
                            scheduledTime: receiverSettings?.checkinTime,
                            timezone: selectedReceiver?.user?.timezone,
                            enrolledSince: selectedReceiver?.joinedAt ?? selectedReceiver?.invitedAt,
                            scheduledWeekdays: scheduledWeekdays
                        )
                        .padding(.horizontal)

                        // Trend Chart
                        CheckInTrendChartView(
                            checkIns: checkIns,
                            days: selectedDays,
                            timezone: selectedReceiver?.user?.timezone
                        )
                        .padding(.horizontal)

                        // Check-in list on a glass card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Check-In Log")
                                .font(.headline)

                            ForEach(checkIns) { checkIn in
                                HStack {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(colors: [DailyOKColor.green400, DailyOKColor.green600], startPoint: .top, endPoint: .bottom))
                                            .frame(width: 12, height: 12)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                    .accessibilityHidden(true)

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
                                .padding(.vertical, 6)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Check-in on \(checkIn.checkedInAt.formatted(date: .abbreviated, time: .shortened)), via \(checkIn.source.rawValue)\(checkIn.mood != nil ? ", mood: \(checkIn.mood!.rawValue)" : "")")
                            }
                        }
                        .padding()
                        .glassCard(style: .thin, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level2)
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom)
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tone: .neutral))
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await exportPDF() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(checkIns.isEmpty)
                }
            }
            .task { await loadMembers() }
            .onChange(of: selectedDays) { _ in
                Task { await loadHistory() }
            }
            .sheet(isPresented: $showPDFShare) {
                if let data = pdfData {
                    ShareSheet(activityItems: [data])
                        .dailyokGlassSheet(style: .regular)
                }
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

        // Load receiver settings for scheduled time
        receiverSettings = try? await SupabaseService.shared.client
            .from("receiver_settings")
            .select()
            .eq("family_member_id", value: receiver.id.uuidString)
            .single()
            .execute()
            .value

        isLoading = false
    }

    private func exportPDF() async {
        guard let receiver = selectedReceiver,
              let family = try? await FamilyService.shared.getFamily() else { return }

        let reportData = CheckInReportGenerator.ReportData(
            receiverName: receiver.user?.displayName ?? "Unknown",
            familyName: family.name,
            checkIns: checkIns,
            periodDays: selectedDays,
            generatedAt: Date()
        )

        pdfData = CheckInReportGenerator.generatePDF(from: reportData)
        showPDFShare = true
    }

    private func moodEmoji(_ mood: Mood) -> String {
        mood.emoji
    }
}

// MARK: - UIKit ShareSheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
