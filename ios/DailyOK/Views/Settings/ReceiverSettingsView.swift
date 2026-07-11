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
    @State private var notifyOwnerOnCheckin = true
    @State private var isLoading = false
    /// True only after settings have been successfully loaded from the server.
    /// Gates Save so the on-screen @State defaults can never overwrite real config
    /// before/without a successful load.
    @State private var hasLoaded = false
    /// True when the initial load failed — show Retry instead of Save.
    @State private var loadFailed = false
    @State private var isSaving = false
    @State private var showSavedConfirmation = false
    @State private var errorMessage: String?
    @State private var receiverMode: ReceiverMode = .standard
    @State private var simpleMode = false
    @State private var audioConfirmationEnabled = false

    // Schedule fields
    @State private var scheduleType: ScheduleType = .daily
    @State private var weekendCheckinTime = Calendar.current.date(from: DateComponents(hour: 10)) ?? Date()
    @State private var customSchedule = DaySchedule.defaultSchedule()
    @State private var schedulePaused = false
    @State private var dayEnabled: [String: Bool] = [
        "mon": true, "tue": true, "wed": true, "thu": true, "fri": true, "sat": true, "sun": true
    ]
    /// A single editable check-in window, carrying a stable identity so removing
    /// a middle row doesn't shift DatePicker bindings to the wrong time
    /// (US-IOS104). Keyed by `id`, never by array offset.
    struct TimeEntry: Identifiable, Equatable {
        let id = UUID()
        var time: Date
    }
    /// One or more check-in times per day key (US-IOS048). A day with more than
    /// one entry produces multiple scheduled windows.
    @State private var dayTimes: [String: [TimeEntry]] = [:]
    /// Upper bound on windows per day to keep the schedule sane.
    private let maxTimesPerDay = 4

    // Manual check-in
    @State private var isSendingManual = false
    @State private var showManualSent = false

    private let gracePeriodOptions = [15, 30, 45, 60, 90, 120]

    /// Quiet-hours start and end must differ (compared at minute granularity);
    /// equal values silently disable the feature server-side (US-IOS111).
    private var quietHoursValid: Bool {
        let cal = Calendar.current
        let s = cal.dateComponents([.hour, .minute], from: quietHoursStart)
        let e = cal.dateComponents([.hour, .minute], from: quietHoursEnd)
        return s.hour != e.hour || s.minute != e.minute
    }

    // Wire format for backend payloads (check-in time, weekend time, quiet hours).
    // POSIX-locked so the 24h "HH:mm" contract is stable across user locales (US-IOS044).
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
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

            // Senior Accessibility (Simple Mode)
            Section {
                Toggle("Simple Mode", isOn: $simpleMode)
                    .accessibilityLabel("Simple mode")
                    .accessibilityHint("Shows an extra-large, low-clutter check-in screen")

                Toggle("Speak Confirmation", isOn: $audioConfirmationEnabled)
                    .accessibilityLabel("Speak confirmation aloud")
                    .accessibilityHint("Says a confirmation out loud after a successful check-in")
            } header: {
                Text("Senior Accessibility")
            } footer: {
                Text("Simple Mode gives \(member.user?.displayName ?? "them") an extra-large, calm, emoji-free check-in button. Speak Confirmation reads a short confirmation aloud — helpful for low vision. (Spoken confirmation is skipped automatically when VoiceOver is on.)")
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
                            // Not icon-only — pair the checkmark with a word so it
                            // reads for everyone (US-IOS105).
                            Label("Sent", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .disabled(isSendingManual)
                // Announce the success to VoiceOver (US-IOS105).
                .announce(showManualSent) { $0 ? "Check-in request sent" : nil }
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
            // Populate a default time for every enabled day the moment the user
            // switches to Custom, so the DatePickers are backed by real (stable)
            // state and edits stick — instead of relying on a per-render fallback.
            .onChange(of: scheduleType) { _, newValue in
                if newValue == .custom { ensureCustomTimesPopulated() }
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

            // Check-In Confirmations
            Section {
                Toggle("Notify Me When They Check In", isOn: $notifyOwnerOnCheckin)
                    .accessibilityLabel("Notify me when they check in")
                    .accessibilityHint("Sends you a push notification each time they tap I'm OK")
            } header: {
                Text("Check-In Confirmations")
            } footer: {
                Text("Get a push notification when \(member.user?.displayName ?? "they") check in, so you know they're OK without opening the app.")
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
                // Start == End would silently disable the feature server-side, so
                // warn and block Save until they differ (US-IOS111).
                if quietHoursEnabled && !quietHoursValid {
                    Text("Start and end times must be different.")
                        .foregroundStyle(.orange)
                } else {
                    Text("No notifications will be sent during quiet hours.")
                }
            }

            // SMS Escalation
            Section {
                Toggle("SMS Fallback", isOn: $smsEscalationEnabled)
                    .accessibilityLabel("SMS escalation fallback")
                    .accessibilityHint("Send SMS when push notifications fail during escalation")
            } header: {
                Text("SMS Escalation")
            } footer: {
                Text("When enabled, an SMS alert is sent to you and viewers if push notifications fail during escalation. Requires a phone number on your account. Msg & data rates may apply. Reply STOP to any message to opt out, or HELP for assistance.")
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
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(tone: .neutral))
        .navigationTitle(member.user?.displayName ?? "Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if loadFailed {
                    // Don't offer Save when we never loaded the real settings —
                    // saving here would write @State defaults over the server row.
                    Button("Retry") {
                        Task { await loadSettings() }
                    }
                    .disabled(isLoading)
                } else {
                    Button {
                        Task { await saveSettings() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || isLoading || !hasLoaded || (quietHoursEnabled && !quietHoursValid))
                }
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
        // errorMessage was assigned on load/manual-check-in/save but never shown,
        // so a failed save looked identical to a success. Surface it.
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
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
                VStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { dayEnabled[day.key] ?? true },
                        set: { isOn in
                            dayEnabled[day.key] = isOn
                            // Ensure an enabled day always has at least one time.
                            if isOn && (dayTimes[day.key]?.isEmpty ?? true) {
                                dayTimes[day.key] = [TimeEntry(time: defaultTimeDate())]
                            }
                        }
                    )) {
                        Text(day.label)
                            .font(.subheadline)
                    }

                    if dayEnabled[day.key] ?? true {
                        // Read dayTimes directly — it's populated proactively on
                        // load and when switching to Custom (ensureCustomTimesPopulated).
                        // The old `?? [TimeEntry(...)]` fallback synthesized a
                        // NEW-identity entry every render, which churned ForEach
                        // identity AND made the DatePicker setter a no-op (its
                        // `guard var arr = dayTimes[day.key]` was nil), so edits
                        // were silently discarded until a day was toggled off/on.
                        let entries = dayTimes[day.key] ?? []
                        // Keyed by entry.id (stable), not array offset, so removing
                        // a middle window doesn't rebind the wrong row (US-IOS104).
                        ForEach(entries) { entry in
                            HStack {
                                Spacer()
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: {
                                            dayTimes[day.key]?.first(where: { $0.id == entry.id })?.time
                                                ?? defaultTimeDate()
                                        },
                                        set: { newVal in
                                            guard var arr = dayTimes[day.key],
                                                  let i = arr.firstIndex(where: { $0.id == entry.id }) else { return }
                                            arr[i].time = newVal
                                            dayTimes[day.key] = arr
                                        }
                                    ),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .frame(width: 100)

                                if entries.count > 1 {
                                    Button {
                                        dayTimes[day.key]?.removeAll { $0.id == entry.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove this time")
                                }
                            }
                        }

                        if entries.count < maxTimesPerDay {
                            Button {
                                var arr = dayTimes[day.key] ?? []
                                arr.append(TimeEntry(time: defaultTimeDate()))
                                dayTimes[day.key] = arr
                            } label: {
                                Label("Add time", systemImage: "plus.circle")
                                    .font(.subheadline)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
        } footer: {
            Text("Toggle off days where no check-in is needed. Add more than one time for days that need several check-ins.")
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
        loadFailed = false
        do {
            let loaded: ReceiverSettings = try await SupabaseService.shared.client
                .from("receiver_settings")
                .select()
                .eq("family_member_id", value: member.id.uuidString)
                .single()
                .execute()
                .value

            settings = loaded

            // Parse wire-format time strings from the backend. POSIX-locked so
            // parsing the fixed 24h format never fails under a user locale (US-IOS044).
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // Accept both HH:mm:ss and HH:mm — if the backend ever returns a
            // seconds-less time, the strict single-format parse returned nil and
            // left checkinTime at its current-wall-clock default, which a later
            // Save would then persist as the daily time (matches the weekend /
            // quiet-hours fields, which already try both).
            formatter.dateFormat = "HH:mm:ss"
            if let time = formatter.date(from: loaded.checkinTime) {
                checkinTime = time
            } else {
                formatter.dateFormat = "HH:mm"
                if let time = formatter.date(from: loaded.checkinTime) {
                    checkinTime = time
                }
            }

            gracePeriod = loaded.gracePeriodMinutes
            reminderInterval = loaded.reminderIntervalMinutes
            escalationEnabled = loaded.escalationEnabled
            moodTrackingEnabled = loaded.moodTrackingEnabled
            smsEscalationEnabled = loaded.smsEscalationEnabled
            notifyOwnerOnCheckin = loaded.notifyOwnerOnCheckin
            receiverMode = loaded.receiverMode
            simpleMode = loaded.simpleMode
            audioConfirmationEnabled = loaded.audioConfirmationEnabled

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

            // Load custom schedule. Dual-read each day's times (multiTimes,
            // falling back to the legacy single field) via DaySchedule.times.
            if let custom = loaded.customSchedule {
                customSchedule = custom
                formatter.dateFormat = "HH:mm"
                for day in DaySchedule.allDays {
                    let timeStrings = custom.times(forDayKey: day.key)
                    dayEnabled[day.key] = !timeStrings.isEmpty
                    let dates = timeStrings.compactMap { formatter.date(from: $0) }
                    if !dates.isEmpty {
                        dayTimes[day.key] = dates.map { TimeEntry(time: $0) }
                    }
                }
            }

            if let qStart = loaded.quietHoursStart, let qEnd = loaded.quietHoursEnd {
                quietHoursEnabled = true
                formatter.dateFormat = "HH:mm:ss"
                if let start = formatter.date(from: qStart) { quietHoursStart = start }
                if let end = formatter.date(from: qEnd) { quietHoursEnd = end }
            }
            // If the loaded schedule is custom but carried no per-day times (e.g.
            // schedule_type=custom with an empty custom_schedule), seed defaults so
            // the pickers are editable rather than dead.
            if scheduleType == .custom { ensureCustomTimesPopulated() }
            hasLoaded = true
        } catch {
            errorMessage = DailyOKError.network(error).localizedDescription
            loadFailed = true
        }
        isLoading = false
    }

    /// Ensure every enabled day has at least one editable check-in window when a
    /// custom schedule is active. Backs the DatePickers with real, stable state
    /// (keyed by TimeEntry.id) so edits persist, rather than a body-level
    /// fallback that re-mints identity each render.
    private func ensureCustomTimesPopulated() {
        for day in DaySchedule.allDays where (dayEnabled[day.key] ?? true) {
            if dayTimes[day.key]?.isEmpty ?? true {
                dayTimes[day.key] = [TimeEntry(time: defaultTimeDate())]
            }
        }
    }

    private func saveSettings() async {
        // Block a custom schedule with every day toggled off: it would persist an
        // empty schedule, meaning the receiver silently never gets a check-in
        // request. Warn instead of saving a broken configuration. (Matches the
        // `?? false` semantics buildCustomSchedule actually persists.)
        if scheduleType == .custom,
           !DaySchedule.allDays.contains(where: { dayEnabled[$0.key] ?? false }) {
            errorMessage = String(localized: "Turn on at least one day — otherwise this person will never get a check-in request.")
            DailyOKHaptics.error()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Select at least one check-in day"))
            return
        }

        isSaving = true

        let timeString = timeFormatter.string(from: checkinTime)

        // Nullable values so disabling quiet hours can explicitly null the columns
        // (omitting them left stale values that silently re-enabled the toggle).
        var updates: [String: String?] = [
            "checkin_time": timeString,
            "grace_period_minutes": String(gracePeriod),
            "reminder_interval_minutes": String(reminderInterval),
            "escalation_enabled": String(escalationEnabled),
            "mood_tracking_enabled": String(moodTrackingEnabled),
            "sms_escalation_enabled": String(smsEscalationEnabled),
            "notify_owner_on_checkin": String(notifyOwnerOnCheckin),
            "receiver_mode": receiverMode.rawValue,
            "schedule_type": scheduleType.rawValue,
            "schedule_paused": String(schedulePaused),
            "simple_mode": String(simpleMode),
            "audio_confirmation_enabled": String(audioConfirmationEnabled),
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
        } else {
            // Explicitly clear so turning Quiet Hours off actually persists.
            updates["quiet_hours_start"] = String?.none
            updates["quiet_hours_end"] = String?.none
        }

        do {
            try await SupabaseService.shared.client
                .from("receiver_settings")
                .update(updates)
                .eq("family_member_id", value: member.id.uuidString)
                .execute()

            // Confirm the save for sighted, haptic, AND VoiceOver users — the
            // green capsule alone is invisible to VoiceOver.
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Settings saved"))
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
            errorMessage = DailyOKError.network(error).localizedDescription
            DailyOKHaptics.error()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Couldn't save settings"))
        }

        isSaving = false
    }

    private func buildCustomSchedule() -> DaySchedule {
        var schedule = DaySchedule()
        var multi: [String: [String]] = [:]
        for day in DaySchedule.allDays {
            guard dayEnabled[day.key] ?? false else {
                schedule[keyPath: day.keyPath] = nil
                continue
            }
            // Sorted, de-duplicated "HH:mm" times for the day.
            let times = (dayTimes[day.key] ?? [TimeEntry(time: defaultTimeDate())])
                .map { timeFormatter.string(from: $0.time) }
            let unique = Array(Set(times)).sorted()
            // Dual-write: legacy single field = earliest time (so old clients
            // still read a valid single time); multiTimes only when there's
            // genuinely more than one window, keeping single-time payloads
            // byte-identical to the previous format.
            schedule[keyPath: day.keyPath] = unique.first
            if unique.count > 1 {
                multi[day.key] = unique
            }
        }
        schedule.multiTimes = multi.isEmpty ? nil : multi
        return schedule
    }

    private func defaultTimeDate() -> Date {
        Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    }
}
