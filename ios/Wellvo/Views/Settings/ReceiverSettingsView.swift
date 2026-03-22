import SwiftUI
import Supabase

struct ReceiverSettingsView: View {
    let member: FamilyMember

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var settings: ReceiverSettings?
    @State private var checkinTime = Date()
    @State private var gracePeriod = 30
    @State private var reminderInterval = 30
    @State private var escalationEnabled = true
    @State private var quietHoursEnabled = false
    @State private var quietHoursStart = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @State private var quietHoursEnd = Calendar.current.date(from: DateComponents(hour: 7)) ?? Date()
    @State private var moodTrackingEnabled = false
    @State private var smsEscalationEnabled = false
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var showSavedConfirmation = false
    @State private var errorMessage: String?
    @State private var receiverMode: ReceiverMode = .standard

    // Schedule fields
    @State private var scheduleType: ScheduleType = .daily
    @State private var weekendCheckinTime = Calendar.current.date(from: DateComponents(hour: 10)) ?? Date()
    @State private var customSchedule = DaySchedule.defaultSchedule()
    @State private var schedulePaused = false
    @State private var dayEnabled: [String: Bool] = [
        "mon": true, "tue": true, "wed": true, "thu": true, "fri": true, "sat": true, "sun": true
    ]
    @State private var dayTimes: [String: Date] = [:]

    // Manual check-in
    @State private var isSendingManual = false
    @State private var showManualSent = false

    private let gracePeriodOptions = [15, 30, 45, 60, 90, 120]
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        Form {
            // Pause Banner
            if schedulePaused {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "pause.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications Paused")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Scheduled check-in notifications are currently paused. Toggle off to resume.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Receiver Mode
            Section {
                Picker("Mode", selection: $receiverMode) {
                    Text("Standard").tag(ReceiverMode.standard)
                    Text("Kid").tag(ReceiverMode.kid)
                }
                .accessibilityLabel("Receiver mode")
                .accessibilityHint("Choose between standard and kid mode for this receiver")
            } header: {
                Text("Receiver Mode")
            } footer: {
                Text("Kid mode provides a fun, engaging experience with expanded mood options and location sharing.")
            }

            // Pause & Manual Notifications
            Section {
                Toggle("Pause Notifications", isOn: $schedulePaused)
                    .accessibilityLabel("Pause scheduled notifications")
                    .accessibilityHint("When enabled, no scheduled check-in notifications will be sent")

                Button {
                    Task { await sendManualCheckIn() }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Send Check-In Now")
                        Spacer()
                        if isSendingManual {
                            ProgressView()
                        } else if showManualSent {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .disabled(isSendingManual)
            } header: {
                Text("Notification Controls")
            } footer: {
                Text("Pause stops all scheduled notifications. Use \"Send Check-In Now\" to manually trigger a check-in request at any time.")
            }

            // Schedule Type Picker
            Section {
                Picker("Schedule", selection: $scheduleType) {
                    ForEach(ScheduleType.allCases, id: \.self) { type in
                        VStack(alignment: .leading) {
                            Text(type.label)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Notification schedule type")

                Text(scheduleType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Check-In Schedule")
            }

            // Schedule Details (varies by type)
            switch scheduleType {
            case .daily:
                dailyScheduleSection
            case .weekdayWeekend:
                weekdayWeekendSection
            case .custom:
                customScheduleSection
            }

            // Timezone
            Section {
                HStack {
                    Text("Timezone")
                    Spacer()
                    Text(member.user?.timezone ?? TimeZone.current.identifier)
                        .foregroundStyle(.secondary)
                }
            }

            // Escalation Chain
            Section {
                Toggle("Escalation Alerts", isOn: $escalationEnabled)
                    .accessibilityLabel("Escalation alerts")
                    .accessibilityHint("When enabled, alerts fire if check-in is missed")

                if escalationEnabled {
                    Picker("Grace Period", selection: $gracePeriod) {
                        ForEach(gracePeriodOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }

                    Picker("Reminder Interval", selection: $reminderInterval) {
                        ForEach(gracePeriodOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }
            } header: {
                Text("Escalation Chain")
            } footer: {
                if escalationEnabled {
                    Text("If \(member.user?.displayName ?? "they") don't check in within \(gracePeriod) minutes, a reminder is sent. After another \(reminderInterval) minutes, you'll be alerted.")
                } else {
                    Text("Escalation is disabled. You won't receive alerts for missed check-ins.")
                }
            }

            // Quiet Hours
            Section {
                Toggle("Quiet Hours", isOn: $quietHoursEnabled)
                    .accessibilityLabel("Quiet hours")
                    .accessibilityHint("When enabled, no notifications during specified hours")

                if quietHoursEnabled {
                    DatePicker("Start", selection: $quietHoursStart, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $quietHoursEnd, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Quiet Hours")
            } footer: {
                Text("No notifications will be sent during quiet hours.")
            }

            // SMS Escalation
            Section {
                Toggle("SMS Fallback", isOn: $smsEscalationEnabled)
                    .accessibilityLabel("SMS escalation fallback")
                    .accessibilityHint("Send SMS when push notifications fail during escalation")
            } header: {
                Text("SMS Escalation")
            } footer: {
                Text("Send an SMS to you and viewers if push notifications fail during escalation. Requires a phone number on your account.")
            }

            // Mood Tracking
            Section {
                Toggle("Mood Tracking", isOn: $moodTrackingEnabled)
                    .accessibilityLabel("Mood tracking")
                    .accessibilityHint("Allow sharing mood after check-in")
            } header: {
                Text("Mood Tracking")
            } footer: {
                Text("After checking in, \(member.user?.displayName ?? "they") can optionally share how they're feeling.")
            }
        }
        .navigationTitle(member.user?.displayName ?? "Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await saveSettings() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            }
        }
        .overlay {
            if showSavedConfirmation {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Settings saved")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.green, in: Capsule())
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .transaction { t in if reduceMotion { t.animation = nil } }
            }
        }
        .task { await loadSettings() }
    }

    // MARK: - Schedule Sections

    private var dailyScheduleSection: some View {
        Section {
            DatePicker("Check-In Time", selection: $checkinTime, displayedComponents: .hourAndMinute)
        } footer: {
            Text("A push notification will be sent at this time every day.")
        }
    }

    private var weekdayWeekendSection: some View {
        Section {
            DatePicker("Weekday Time (Mon\u{2013}Fri)", selection: $checkinTime, displayedComponents: .hourAndMinute)
            DatePicker("Weekend Time (Sat\u{2013}Sun)", selection: $weekendCheckinTime, displayedComponents: .hourAndMinute)
        } footer: {
            Text("Different check-in times for weekdays and weekends.")
        }
    }

    private var customScheduleSection: some View {
        Section {
            ForEach(DaySchedule.allDays, id: \.key) { day in
                HStack {
                    Toggle(isOn: Binding(
                        get: { dayEnabled[day.key] ?? true },
                        set: { dayEnabled[day.key] = $0 }
                    )) {
                        Text(day.label)
                            .font(.subheadline)
                    }

                    if dayEnabled[day.key] ?? true {
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { dayTimes[day.key] ?? defaultTimeDate() },
                                set: { dayTimes[day.key] = $0 }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .frame(width: 100)
                    }
                }
            }
        } footer: {
            Text("Toggle off days where no check-in is needed. Set individual times for each active day.")
        }
    }

    // MARK: - Manual Check-In

    private func sendManualCheckIn() async {
        isSendingManual = true
        do {
            try await CheckInService.shared.sendOnDemandCheckIn(
                receiverId: member.userId,
                familyId: member.familyId
            )
            showManualSent = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showManualSent = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isSendingManual = false
    }

    // MARK: - Data

    private func loadSettings() async {
        isLoading = true
        do {
            let loaded: ReceiverSettings = try await SupabaseService.shared.client
                .from("receiver_settings")
                .select()
                .eq("family_member_id", value: member.id.uuidString)
                .single()
                .execute()
                .value

            settings = loaded

            // Parse time string to Date
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            if let time = formatter.date(from: loaded.checkinTime) {
                checkinTime = time
            }

            gracePeriod = loaded.gracePeriodMinutes
            reminderInterval = loaded.reminderIntervalMinutes
            escalationEnabled = loaded.escalationEnabled
            moodTrackingEnabled = loaded.moodTrackingEnabled
            smsEscalationEnabled = loaded.smsEscalationEnabled
            receiverMode = loaded.receiverMode

            // Schedule fields
            scheduleType = loaded.scheduleType
            schedulePaused = loaded.schedulePaused

            if let weekendTime = loaded.weekendCheckinTime {
                formatter.dateFormat = "HH:mm:ss"
                if let wt = formatter.date(from: weekendTime) {
                    weekendCheckinTime = wt
                } else {
                    formatter.dateFormat = "HH:mm"
                    if let wt = formatter.date(from: weekendTime) {
                        weekendCheckinTime = wt
                    }
                }
            }

            // Load custom schedule
            if let custom = loaded.customSchedule {
                customSchedule = custom
                for day in DaySchedule.allDays {
                    let timeStr = custom[keyPath: day.keyPath]
                    dayEnabled[day.key] = timeStr != nil
                    if let timeStr {
                        formatter.dateFormat = "HH:mm"
                        if let date = formatter.date(from: timeStr) {
                            dayTimes[day.key] = date
                        }
                    }
                }
            }

            if let qStart = loaded.quietHoursStart, let qEnd = loaded.quietHoursEnd {
                quietHoursEnabled = true
                formatter.dateFormat = "HH:mm:ss"
                if let start = formatter.date(from: qStart) { quietHoursStart = start }
                if let end = formatter.date(from: qEnd) { quietHoursEnd = end }
            }
        } catch {
            errorMessage = WellvoError.network(error).localizedDescription
        }
        isLoading = false
    }

    private func saveSettings() async {
        isSaving = true

        let timeString = timeFormatter.string(from: checkinTime)

        var updates: [String: String] = [
            "checkin_time": timeString,
            "grace_period_minutes": String(gracePeriod),
            "reminder_interval_minutes": String(reminderInterval),
            "escalation_enabled": String(escalationEnabled),
            "mood_tracking_enabled": String(moodTrackingEnabled),
            "sms_escalation_enabled": String(smsEscalationEnabled),
            "receiver_mode": receiverMode.rawValue,
            "schedule_type": scheduleType.rawValue,
            "schedule_paused": String(schedulePaused),
        ]

        // Schedule-specific fields
        switch scheduleType {
        case .weekdayWeekend:
            updates["weekend_checkin_time"] = timeFormatter.string(from: weekendCheckinTime)
        case .custom:
            // Build custom schedule JSON
            let schedule = buildCustomSchedule()
            if let jsonData = try? JSONEncoder().encode(schedule),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                updates["custom_schedule"] = jsonString
            }
        case .daily:
            break
        }

        if quietHoursEnabled {
            updates["quiet_hours_start"] = timeFormatter.string(from: quietHoursStart)
            updates["quiet_hours_end"] = timeFormatter.string(from: quietHoursEnd)
        }

        do {
            try await SupabaseService.shared.client
                .from("receiver_settings")
                .update(updates)
                .eq("family_member_id", value: member.id.uuidString)
                .execute()

            if reduceMotion {
                showSavedConfirmation = true
            } else {
                withAnimation { showSavedConfirmation = true }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if reduceMotion {
                showSavedConfirmation = false
            } else {
                withAnimation { showSavedConfirmation = false }
            }
        } catch {
            errorMessage = WellvoError.network(error).localizedDescription
        }

        isSaving = false
    }

    private func buildCustomSchedule() -> DaySchedule {
        var schedule = DaySchedule()
        for day in DaySchedule.allDays {
            if dayEnabled[day.key] ?? false {
                let time = dayTimes[day.key] ?? defaultTimeDate()
                schedule[keyPath: day.keyPath] = timeFormatter.string(from: time)
            } else {
                schedule[keyPath: day.keyPath] = nil
            }
        }
        return schedule
    }

    private func defaultTimeDate() -> Date {
        Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    }
}
