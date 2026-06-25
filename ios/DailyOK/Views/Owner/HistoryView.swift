import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedReceiver: FamilyMember?
    @State private var checkIns: [CheckIn] = []
    @State private var members: [FamilyMember] = []
    @State private var isLoading = false
    @State private var selectedDays = 30
    @State private var receiverSettings: ReceiverSettings?
    @State private var showPDFShare = false
    @State private var pdfData: Data?
    @State private var isExporting = false
    @State private var exportError: String?

    /// Calendar weekday numbers (1=Sun…7=Sat) the selected receiver is scheduled
    /// to check in on, so the heatmap doesn't paint unscheduled/paused days as
    /// "missed". Nil → treat every day as scheduled (legacy behavior).
    private var scheduledWeekdays: Set<Int>? {
        receiverSettings?.scheduledWeekdays
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
                                            .frame(minHeight: 44) // comfortable tap target
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
                            scheduledWeekdays: scheduledWeekdays,
                            settings: receiverSettings
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
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(checkIns.isEmpty || isExporting)
                    .accessibilityLabel(isExporting ? "Generating report" : "Export report")
                }
            }
            .alert("Export Failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .refreshable { await loadMembers() }
            .task { await loadMembers() }
            .onChange(of: selectedDays) { _ in
                Task { await loadHistory() }
            }
            // SwiftUI keeps tabs alive, so `.task` only fires once. Reload when the
            // owner returns to the History tab or foregrounds the app so the member
            // list / data isn't stale after inviting or removing a receiver.
            .onChange(of: appState.selectedTab) { newTab in
                if newTab == .history {
                    Task { await loadMembers() }
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    Task { await loadMembers() }
                }
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
        // Clear the previous receiver's data/schedule first so switching
        // receivers doesn't briefly render the old data under the new name
        // (US-IOS111).
        checkIns = []
        receiverSettings = nil
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
        guard !isExporting else { return }
        guard let receiver = selectedReceiver,
              let family = try? await FamilyService.shared.getFamily() else { return }

        isExporting = true
        defer { isExporting = false }

        let reportData = CheckInReportGenerator.ReportData(
            receiverName: receiver.user?.displayName ?? "Unknown",
            familyName: family.name,
            checkIns: checkIns,
            periodDays: selectedDays,
            generatedAt: Date(),
            timezone: receiver.user?.timezone
        )

        // Generate off the main actor so a large (e.g. 90-day) report can't
        // freeze the UI while the spinner shows. ReportData is Sendable.
        let data = await Task.detached(priority: .userInitiated) {
            CheckInReportGenerator.generatePDF(from: reportData)
        }.value

        // Don't present an empty share sheet — surface an error instead.
        guard !data.isEmpty else {
            exportError = "Couldn't generate the report. Please try again."
            return
        }
        pdfData = data
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
