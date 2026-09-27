import SwiftUI
import Supabase

/// Owner's detail screen for one receiver: schedule, pause, escalation, quiet
/// hours, a manual "check on them now", and the way into their care notes.
///
/// What it guarantees:
/// - Nothing on screen is invented: the form only appears once the real row
///   has loaded; a failed load shows an inline retry, not editable defaults.
///   A member with no settings row is told so ("No check-in schedule yet"):
///   the form starts on defaults, reads as unsaved, and Save creates the row.
/// - Save writes only what the owner changed (a receiver's own Simple Mode /
///   Spoken Confirmation choices survive), writes `custom_schedule` as a JSON
///   object, and only reports "Saved" when a row was actually updated.
/// - Edits are never lost silently: Back asks to save or discard.
/// - A check-in that could never be asked (all days off, or inside quiet
///   hours) can't be saved.
struct ReceiverSettingsView: View {
    let member: FamilyMember

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var settings: ReceiverSettings?
    @State private var checkinTime = Calendar.current.date(from: DateComponents(hour: 8)) ?? Date()
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
    /// The form (and Save) only exist after this, so on-screen defaults can
    /// never be shown as real or written over the server row.
    @State private var hasLoaded = false
    /// True when the load failed — the screen shows an inline retry.
    @State private var loadFailed = false
    /// The member is in the family but has no receiver_settings row (a join
    /// from before 00054). Dispatch needs that row, so no check-in is being
    /// sent. The form starts on defaults and Save creates the row.
    @State private var needsFirstSave = false
    @State private var isSaving = false
    @State private var showSavedConfirmation = false
    /// A failed save or manual check-in.
    @State private var errorMessage: String?
    /// A schedule the server couldn't act on (shown as "Check the schedule").
    @State private var validationMessage: String?
    /// Informational note after a save (e.g. auto-resume unsupported).
    @State private var saveNote: String?
    @State private var receiverMode: ReceiverMode = .standard
    @State private var simpleMode = false
    @State private var audioConfirmationEnabled = false
    /// The form as loaded (or last saved). Save diffs against it; Back warns
    /// when the form differs from it.
    @State private var loadedForm: ReceiverSettingsForm?
    @State private var showUnsavedChangesDialog = false
    @State private var showEscalationOffConfirm = false
    /// The loaded row is Custom but holds no readable schedule, so no
    /// check-in is being sent until the owner saves one.
    @State private var customScheduleMissing = false
    /// Title for `errorMessage` ("Couldn't save" / "Couldn't send").
    @State private var errorTitle = String(localized: "Couldn't save")
    /// Owner + viewers, for the escalation timeline and the owner's phone.
    @State private var careTeam: [FamilyMember] = []

    // Schedule fields
    @State private var scheduleType: ScheduleType = .daily
    @State private var weekendCheckinTime = Calendar.current.date(from: DateComponents(hour: 10)) ?? Date()
    @State private var schedulePaused = false
    @State private var pauseLength: ReceiverSettingsForm.PauseLength = .untilResumed
    @State private var pauseResumeDay = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
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
    private enum ManualResult: Equatable {
        case sent, resent, noDevice
    }
    @State private var isSendingManual = false
    @State private var manualResult: ManualResult?
    @State private var manualSentAt: Date?

    private let baseIntervalOptions = [5, 10, 15, 30, 45, 60, 90, 120]

    /// Options for a picker, always including the stored value so a value set
    /// elsewhere (Android, an invite) never shows as a blank selection.
    private func intervalOptions(including value: Int) -> [Int] {
        baseIntervalOptions.contains(value) ? baseIntervalOptions : (baseIntervalOptions + [value]).sorted()
    }

    /// Readable deep tints: system green/orange on white fall near 2:1.
    private static let successText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? .systemGreen
            : UIColor(red: 0.082, green: 0.502, blue: 0.239, alpha: 1)
    })
    private static let warningText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? .systemOrange
            : UIColor(red: 0.62, green: 0.33, blue: 0.0, alpha: 1)
    })

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

    private var name: String {
        let n = member.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? String(localized: "this person") : n
    }

    // MARK: - Derived state

    /// The form as currently edited, in wire format.
    private var currentForm: ReceiverSettingsForm {
        ReceiverSettingsForm(
            checkinTime: timeFormatter.string(from: checkinTime),
            gracePeriodMinutes: gracePeriod,
            reminderIntervalMinutes: reminderInterval,
            escalationEnabled: escalationEnabled,
            moodTrackingEnabled: moodTrackingEnabled,
            smsEscalationEnabled: smsEscalationEnabled,
            notifyOwnerOnCheckin: notifyOwnerOnCheckin,
            receiverMode: receiverMode,
            scheduleType: scheduleType,
            schedulePaused: schedulePaused,
            pausedUntil: schedulePaused ? pauseResumeDate : nil,
            simpleMode: simpleMode,
            audioConfirmationEnabled: audioConfirmationEnabled,
            weekendCheckinTime: scheduleType == .weekdayWeekend ? timeFormatter.string(from: weekendCheckinTime) : nil,
            customSchedule: scheduleType == .custom ? buildCustomSchedule() : nil,
            quietHoursStart: quietHoursEnabled ? timeFormatter.string(from: quietHoursStart) : nil,
            quietHoursEnd: quietHoursEnabled ? timeFormatter.string(from: quietHoursEnd) : nil
        )
    }

    private var hasUnsavedChanges: Bool {
        guard hasLoaded, let loadedForm else { return false }
        return needsFirstSave || currentForm != loadedForm
    }

    /// The zone dispatch actually uses (receiver_settings.timezone), falling
    /// back to the user row, then this device.
    private var receiverTimeZone: TimeZone {
        if let id = settings?.timezone, let tz = TimeZone(identifier: id) { return tz }
        if let id = member.user?.timezone, let tz = TimeZone(identifier: id) { return tz }
        return .current
    }

    private var receiverCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = receiverTimeZone
        return cal
    }

    private var zoneDiffersFromMine: Bool {
        receiverTimeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT()
    }

    private var receiverZoneName: String {
        receiverTimeZone.localizedName(for: .generic, locale: .current) ?? receiverTimeZone.identifier
    }

    private var pauseResumeDate: Date? {
        ReceiverSettingsForm.resumeDate(
            for: pauseLength,
            now: Date(),
            chosenDay: pauseResumeDay,
            receiverCalendar: receiverCalendar
        )
    }

    /// Scheduled times that fall inside quiet hours (never asked at their time).
    private var quietHourConflicts: [String] {
        guard quietHoursEnabled, quietHoursValid else { return [] }
        return currentForm.timesInsideQuietHours
    }

    private var viewerNames: [String] {
        careTeam
            .filter { $0.role == .viewer && $0.status == .active }
            .compactMap { $0.user?.displayName }
            .filter { !$0.isEmpty }
            .sorted()
    }

    // MARK: - Body

    var body: some View {
        content
            .scrollContentBackground(.hidden)
            .background(AmbientBackground(tone: .neutral))
            .navigationTitle(member.user?.displayName ?? String(localized: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            // Leaving with unsaved edits asks first; the swipe-back gesture is
            // disabled along with the system back button.
            .navigationBarBackButtonHidden(hasUnsavedChanges)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if hasUnsavedChanges {
                        Button {
                            showUnsavedChangesDialog = true
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityHint("You have unsaved changes")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if hasLoaded {
                        Button {
                            Task { await saveSettings() }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save")
                            }
                        }
                        .disabled(isSaving || isLoading || !hasUnsavedChanges)
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
                        // Deep green so the white label passes 4.5:1.
                        .background(DailyOKColor.green700, in: Capsule())
                        .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .transaction { t in if reduceMotion { t.animation = nil } }
                }
            }
            // Load once per screen. `.task` re-runs every time the view
            // reappears (e.g. after switching tabs), and reloading then threw
            // away some edits but not others.
            .task {
                if !hasLoaded && member.status != .invited { await loadSettings() }
            }
            .alert(
                errorTitle,
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                "Check the schedule",
                isPresented: Binding(
                    get: { validationMessage != nil },
                    set: { if !$0 { validationMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "")
            }
            .alert(
                "Saved",
                isPresented: Binding(
                    get: { saveNote != nil },
                    set: { if !$0 { saveNote = nil } }
                )
            ) {
                Button("OK", role: .cancel) { saveNote = nil }
            } message: {
                Text(saveNote ?? "")
            }
            .confirmationDialog(
                "Save changes to \(name)'s settings?",
                isPresented: $showUnsavedChangesDialog,
                titleVisibility: .visible
            ) {
                Button("Save") {
                    Task {
                        if await saveSettings() { dismiss() }
                    }
                }
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .confirmationDialog(
                "Turn off alerts for \(name)?",
                isPresented: $showEscalationOffConfirm,
                titleVisibility: .visible
            ) {
                Button("Turn Off Alerts", role: .destructive) { escalationEnabled = false }
                Button("Keep Alerts On", role: .cancel) {}
            } message: {
                Text("No one will be told if \(name) doesn't answer a check-in.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if member.status == .invited {
            notJoinedState
        } else if hasLoaded {
            settingsForm
        } else if loadFailed {
            loadErrorState
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(name)'s settings…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private var notJoinedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("\(name) hasn't joined yet")
                .font(.headline)
            Text("Their check-in time comes from the invite. Once they join, you can change their schedule and alerts here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var loadErrorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Couldn't load \(name)'s settings")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Check your connection and try again. Nothing has been changed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadSettings() }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Try Again")
                }
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(isLoading)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Form

    private var settingsForm: some View {
        Form {
            if needsFirstSave {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No check-in schedule yet", systemImage: "calendar.badge.exclamationmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Self.warningText)
                        Text("\(name) isn't being asked to check in. Choose a time below and tap Save to start daily check-ins.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if member.status != .active {
                Section {
                    Label("\(name) isn't active in your family, so these settings won't take effect.",
                          systemImage: "person.crop.circle.badge.xmark")
                        .font(.subheadline)
                        .foregroundStyle(Self.warningText)
                }
            }

            if schedulePaused {
                pauseBanner
            }

            rightNowSection

            scheduleTypeSection

            // Schedule Details (varies by type)
            switch scheduleType {
            case .daily:
                dailyScheduleSection
            case .weekdayWeekend:
                weekdayWeekendSection
            case .custom:
                customScheduleSection
            }

            timezoneSection

            pauseSection

            escalationSection

            howAlertsArriveSection

            quietHoursSection

            // Check-In Confirmations
            Section {
                Toggle("Notify Me When They Check In", isOn: $notifyOwnerOnCheckin)
                    .accessibilityLabel("Notify me when \(name) checks in")
                    .accessibilityHint("Sends you a push notification each time they tap I'm OK")
            } header: {
                Text("Check-In Confirmations")
            } footer: {
                Text("Get a notification when \(name) checks in, so you know they're OK without opening the app.")
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
                Text("Kid mode shows a playful check-in screen with kid-friendly replies and more mood choices.")
            }

            // Display & accessibility (Simple Mode)
            if receiverMode != .kid || simpleMode || audioConfirmationEnabled {
                Section {
                    Toggle("Simple Mode", isOn: $simpleMode)
                        .accessibilityLabel("Simple mode")
                        .accessibilityHint("Shows an extra-large, low-clutter check-in screen")

                    Toggle("Speak Confirmation", isOn: $audioConfirmationEnabled)
                        .accessibilityLabel("Speak confirmation aloud")
                        .accessibilityHint("Says a confirmation out loud after a successful check-in")
                } header: {
                    Text("Display & Accessibility")
                } footer: {
                    Text("Simple Mode gives \(name) an extra-large, calm, emoji-free check-in button. Speak Confirmation reads a short confirmation aloud — helpful for low vision. (Spoken confirmation is skipped automatically when VoiceOver is on.) \(name) can also change these on their own phone.")
                }
            }

            // Mood Tracking
            Section {
                Toggle("Mood Tracking", isOn: $moodTrackingEnabled)
                    .accessibilityLabel("Mood tracking")
                    .accessibilityHint("Allow sharing mood after check-in")
            } header: {
                Text("Mood Tracking")
            } footer: {
                Text("After checking in, \(name) can optionally share how they're feeling.")
            }
        }
    }

    // MARK: - Sections

    private var pauseBanner: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Self.warningText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pauseBannerTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(loadedForm?.schedulePaused == true
                         ? String(localized: "\(name) isn't being asked to check in, and no one is alerted.")
                         : String(localized: "Will pause when you tap Save."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var pauseBannerTitle: String {
        if let resume = pauseResumeDate {
            return String(localized: "Check-ins paused until \(formatResume(resume))")
        }
        return String(localized: "Check-ins paused")
    }

    private func formatResume(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = receiverTimeZone
        f.setLocalizedDateFormatFromTemplate("EEE MMM d j:mm")
        var text = f.string(from: date)
        if zoneDiffersFromMine, let abbr = receiverTimeZone.abbreviation(for: date) {
            text += " \(abbr)"
        }
        return text
    }

    private var rightNowSection: some View {
        Section {
            Button {
                guard !isSendingManual else { return }
                isSendingManual = true
                Task { await sendManualCheckIn() }
            } label: {
                HStack {
                    Image(systemName: "bell.badge")
                    Text("Check on \(name) now")
                    Spacer()
                    if isSendingManual {
                        ProgressView()
                    }
                }
                .frame(minHeight: 44)
            }
            .disabled(isSendingManual || member.status != .active)
            .accessibilityHint("Sends \(name) a check-in request right away")

            if let manualResult {
                manualResultRow(manualResult)
            }

            NavigationLink {
                CareNotesView(familyId: member.familyId, receiverId: member.userId, receiverName: name)
            } label: {
                Label("Care notes", systemImage: "note.text")
            }
            .accessibilityHint("Open the shared care notes for \(name)")
        } header: {
            Text("Right Now")
        } footer: {
            Text("Asks \(name) to check in now, with the same reminders and alerts as a scheduled check-in.")
        }
    }

    @ViewBuilder
    private func manualResultRow(_ result: ManualResult) -> some View {
        let at = manualSentAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        switch result {
        case .sent:
            Label("Sent at \(at) · waiting for an answer", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Self.successText)
        case .resent:
            Label("Already asked a moment ago — reminder re-sent at \(at)", systemImage: "arrow.clockwise.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Self.successText)
        case .noDevice:
            VStack(alignment: .leading, spacing: 8) {
                Label("Saved, but \(name)'s phone couldn't be notified. Call instead?",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Self.warningText)
                ContactQuickActions(name: name, phone: member.user?.phone)
            }
        }
    }

    private var scheduleTypeSection: some View {
        Section {
            Picker("Schedule", selection: $scheduleType) {
                ForEach(ScheduleType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Check-in schedule type")

            Text(scheduleType.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Check-In Schedule")
        }
        // Populate times for every enabled day the moment the user switches to
        // Custom, seeded from the times already chosen (not a flat 8:00).
        .onChange(of: scheduleType) { oldValue, newValue in
            if newValue == .custom {
                ensureCustomTimesPopulated(useWeekendTime: oldValue == .weekdayWeekend)
            }
        }
    }

    @ViewBuilder
    private var quietConflictWarning: some View {
        if !quietHourConflicts.isEmpty {
            Text(quietConflictText)
                .foregroundStyle(Self.warningText)
        }
    }

    private var quietConflictText: String {
        let times = ListFormatter.localizedString(byJoining: quietHourConflicts.map { displayTime($0) })
        let range = "\(displayTime(timeFormatter.string(from: quietHoursStart)))–\(displayTime(timeFormatter.string(from: quietHoursEnd)))"
        return String(localized: "\(times) is inside quiet hours (\(range)), so \(name) wouldn't be asked then. Move the check-in or change quiet hours.")
    }

    private var dailyScheduleSection: some View {
        Section {
            DatePicker("Check-In Time", selection: $checkinTime, displayedComponents: .hourAndMinute)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                quietConflictWarning
                Text("\(name) is asked at this time every day.")
            }
        }
    }

    private var weekdayWeekendSection: some View {
        Section {
            DatePicker("Weekday Time (Mon\u{2013}Fri)", selection: $checkinTime, displayedComponents: .hourAndMinute)
            DatePicker("Weekend Time (Sat\u{2013}Sun)", selection: $weekendCheckinTime, displayedComponents: .hourAndMinute)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                quietConflictWarning
                Text("Different check-in times for weekdays and weekends.")
            }
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
                                dayTimes[day.key] = [TimeEntry(time: seedTime(forDayKey: day.key))]
                            }
                        }
                    )) {
                        Text(day.label)
                            .font(.subheadline)
                    }

                    if dayEnabled[day.key] ?? true {
                        // Read dayTimes directly — it's populated on load and
                        // when switching to Custom (ensureCustomTimesPopulated),
                        // so every picker is backed by stable state.
                        let entries = dayTimes[day.key] ?? []
                        // Keyed by entry.id (stable), not array offset, so removing
                        // a middle window doesn't rebind the wrong row (US-IOS104).
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            HStack {
                                Spacer()
                                DatePicker(
                                    "\(day.label) check-in \(index + 1)",
                                    selection: Binding(
                                        get: {
                                            dayTimes[day.key]?.first(where: { $0.id == entry.id })?.time
                                                ?? seedTime(forDayKey: day.key)
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
                                .accessibilityLabel("\(day.label) check-in \(index + 1)")

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
                                    .accessibilityLabel("Remove \(day.label) \(entry.time.formatted(date: .omitted, time: .shortened)) check-in")
                                }
                            }
                        }

                        if entries.count < maxTimesPerDay {
                            Button {
                                var arr = dayTimes[day.key] ?? []
                                arr.append(TimeEntry(time: nextAddedTime(after: arr.map(\.time))))
                                dayTimes[day.key] = arr
                            } label: {
                                Label("Add time", systemImage: "plus.circle")
                                    .font(.subheadline)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityLabel("Add another \(day.label) check-in time")
                        }
                    }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if customScheduleMissing {
                    Text("No custom schedule is saved yet, so \(name) isn't being asked to check in. Review the times and tap Save.")
                        .foregroundStyle(Self.warningText)
                }
                quietConflictWarning
                Text("Toggle off days where no check-in is needed. Add more than one time for days that need several check-ins.")
            }
        }
    }

    private var timezoneSection: some View {
        Section {
            HStack {
                Text("\(name)'s time zone")
                Spacer()
                Text(receiverZoneName)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        } footer: {
            Text(timezoneFooter)
        }
    }

    private var timezoneFooter: String {
        let nowThere = Date().formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: receiverTimeZone))
        var text = String(localized: "Check-in times and quiet hours are in \(name)'s local time (it's \(nowThere) there now).")
        if zoneDiffersFromMine, let first = currentForm.scheduledTimes.first,
           let mine = ownerLocalEquivalent(of: first) {
            text += " " + String(localized: "\(displayTime(first)) for \(name) is \(mine) for you.")
        }
        return text
    }

    private var pauseSection: some View {
        Section {
            Toggle("Pause check-ins for \(name)", isOn: $schedulePaused)
                .accessibilityHint("While paused, \(name) isn't asked to check in and no one is alerted")

            if schedulePaused {
                Picker("How long", selection: $pauseLength) {
                    ForEach(ReceiverSettingsForm.PauseLength.allCases) { length in
                        Text(length.label).tag(length)
                    }
                }
                if pauseLength == .onDate {
                    DatePicker(
                        "Resume on",
                        selection: $pauseResumeDay,
                        // Start of tomorrow, so a day pinned from a saved
                        // pause (noon) is never below the range and clamped.
                        in: Calendar.current.startOfDay(
                            for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                        )...,
                        displayedComponents: .date
                    )
                }
            }
        } header: {
            Text("Pause")
        } footer: {
            Text("While paused, \(name) isn't asked and no one is alerted about missed check-ins. A check-in that has already been sent keeps its reminders and alerts — use Stop alerts on the dashboard for that.")
        }
    }

    private var escalationSection: some View {
        Section {
            Toggle("Escalation Alerts", isOn: Binding(
                get: { escalationEnabled },
                set: { newValue in
                    // Turning alerts off removes the app's safety net for this
                    // person — confirm it.
                    if newValue { escalationEnabled = true } else { showEscalationOffConfirm = true }
                }
            ))
            .accessibilityLabel("Escalation alerts")
            .accessibilityHint("When on, you and your viewers are alerted if a check-in is missed")

            if escalationEnabled {
                Picker("First reminder after", selection: $gracePeriod) {
                    ForEach(intervalOptions(including: gracePeriod), id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }

                Picker("Then every", selection: $reminderInterval) {
                    ForEach(intervalOptions(including: reminderInterval), id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
            }
        } header: {
            Text("Escalation Chain")
        } footer: {
            if escalationEnabled {
                Text(escalationTimelineText)
            } else {
                Text("Escalation is off. No one will be alerted if \(name) misses a check-in.")
            }
        }
    }

    /// A concrete timeline from the current pickers: who hears, and when.
    private var escalationTimelineText: String {
        let base = currentForm.scheduledTimes.first.flatMap(ReceiverSettingsForm.minutesOfDay)
        func when(_ offset: Int) -> String {
            guard let base else {
                return offset == 0 ? String(localized: "At check-in time") : String(localized: "After \(offset) min")
            }
            return displayTime(minutesOfDay: base + offset)
        }
        var lines: [String] = []
        if let first = currentForm.scheduledTimes.first {
            lines.append(String(localized: "If \(name) doesn't answer the \(displayTime(first)) check-in:"))
        } else {
            lines.append(String(localized: "If \(name) doesn't answer:"))
        }
        let viewers = viewerNames
        for step in ReceiverSettingsForm.escalationSteps(gracePeriodMinutes: gracePeriod, reminderIntervalMinutes: reminderInterval) {
            let time = when(step.offsetMinutes)
            switch step.kind {
            case .asked:
                continue
            case .reminder:
                lines.append(String(localized: "\(time) — a reminder to \(name)"))
            case .ownerAlerted:
                lines.append(String(localized: "\(time) — you're alerted"))
            case .viewersAlerted:
                if viewers.isEmpty {
                    lines.append(String(localized: "\(time) — viewers would be alerted (you have none yet)"))
                } else {
                    let names = ListFormatter.localizedString(byJoining: viewers)
                    lines.append(String(localized: "\(time) — \(names) alerted"))
                }
            case .missed:
                lines.append(String(localized: "\(time) — marked Missed"))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Daily OK doesn't send text messages any more (server SMS needs an A2P
    /// 10DLC registration). The old "Text Alerts" toggle is gone; its
    /// `sms_escalation_enabled` column is still loaded and saved unchanged so
    /// older app builds keep reading the value they wrote, but nothing acts on
    /// it. Alerts are notifications; a text is sent by the caregiver from their
    /// own phone, pre-filled, from the dashboard card.
    private var howAlertsArriveSection: some View {
        Section {
            Label {
                Text("Alerts arrive as notifications on your phone and on each viewer's phone.")
            } icon: {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            Label {
                Text("To reach \(name), tap Text on their card. Your Messages app opens with a short note ready to send from your own number.")
            } icon: {
                Image(systemName: "message.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
        } header: {
            Text("How Alerts Arrive")
        } footer: {
            Text("Daily OK doesn't send text messages. Allow Daily OK notifications, including Time Sensitive ones, so alerts get through Focus.")
        }
    }

    private var quietHoursSection: some View {
        Section {
            Toggle("Quiet Hours", isOn: $quietHoursEnabled)
                .accessibilityLabel("Quiet hours")
                .accessibilityHint("When on, no scheduled check-ins are sent during these hours")

            if quietHoursEnabled {
                DatePicker("Start", selection: $quietHoursStart, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $quietHoursEnd, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Quiet Hours")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                // Start == End would silently disable the feature server-side (US-IOS111).
                if quietHoursEnabled && !quietHoursValid {
                    Text("Start and end times must be different.")
                        .foregroundStyle(Self.warningText)
                }
                quietConflictWarning
                Text("No scheduled check-ins are sent during quiet hours. Reminders and alerts for a check-in that's already overdue still go out.")
            }
        }
    }

    // MARK: - Time helpers

    /// "08:00" → "8:00 AM" in the user's locale (a wall-clock time).
    private func displayTime(_ hhmm: String) -> String {
        guard let m = ReceiverSettingsForm.minutesOfDay(hhmm) else { return hhmm }
        return displayTime(minutesOfDay: m)
    }

    private func displayTime(minutesOfDay: Int) -> String {
        let m = ((minutesOfDay % 1440) + 1440) % 1440
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let date = cal.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: m / 60, minute: m % 60)) ?? Date()
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: cal.timeZone))
    }

    /// The owner's clock time for a receiver-local "HH:mm" today.
    private func ownerLocalEquivalent(of hhmm: String) -> String? {
        guard let m = ReceiverSettingsForm.minutesOfDay(hhmm) else { return nil }
        let cal = receiverCalendar
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = m / 60
        comps.minute = m % 60
        guard let instant = cal.date(from: comps) else { return nil }
        return instant.formatted(date: .omitted, time: .shortened)
    }

    /// Seed for a custom day: the time the owner already chose (the weekend
    /// time for Sat/Sun when coming from Weekday/Weekend), so switching to
    /// Custom keeps it instead of resetting every day to 8:00.
    private func seedTime(forDayKey key: String, useWeekendTime: Bool = false) -> Date {
        if useWeekendTime, key == "sat" || key == "sun" {
            return weekendCheckinTime
        }
        return checkinTime
    }

    /// A new window defaults to three hours after the latest existing one
    /// (capped at 23:00), not a duplicate that save would silently drop.
    private func nextAddedTime(after existing: [Date]) -> Date {
        let cal = Calendar.current
        guard let latest = existing.max() else { return checkinTime }
        let comps = cal.dateComponents([.hour, .minute], from: latest)
        let minutes = min(((comps.hour ?? 8) * 60 + (comps.minute ?? 0)) + 180, 23 * 60)
        return cal.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? latest
    }

    // MARK: - Manual Check-In

    private func sendManualCheckIn() async {
        // isSendingManual is set by the button before this task starts, so a
        // double tap can't send twice.
        defer { isSendingManual = false }
        manualResult = nil
        do {
            let result = try await CheckInService.shared.requestOnDemandCheckIn(
                receiverId: member.userId,
                familyId: member.familyId
            )
            manualSentAt = Date()
            if result.deliveredDevices == 0 {
                manualResult = .noDevice
                DailyOKHaptics.warning()
                UIAccessibility.post(notification: .announcement,
                                     argument: String(localized: "Request saved, but \(name)'s phone couldn't be notified"))
            } else if result.deduplicated == true {
                manualResult = .resent
                DailyOKHaptics.success()
                UIAccessibility.post(notification: .announcement,
                                     argument: String(localized: "\(name) was already asked a moment ago. Reminder re-sent."))
            } else {
                manualResult = .sent
                DailyOKHaptics.success()
                UIAccessibility.post(notification: .announcement,
                                     argument: String(localized: "Check-in request sent to \(name)"))
            }
        } catch {
            DailyOKHaptics.error()
            errorTitle = String(localized: "Couldn't send")
            errorMessage = String(localized: "Couldn't ask \(name) to check in: \(error.localizedDescription)")
        }
    }

    // MARK: - Data

    private func loadSettings() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            // An array, not .single(): a missing row is an answer ("no
            // schedule yet"), not a failure. .single() turned it into
            // "Check your connection" with a Try Again that could never work.
            let rows: [ReceiverSettings] = try await SupabaseService.shared.client
                .from("receiver_settings")
                .select()
                .eq("family_member_id", value: member.id.uuidString)
                .limit(1)
                .execute()
                .value

            guard let loaded = rows.first else {
                // Defaults on screen, clearly marked as not saved yet.
                needsFirstSave = true
                loadedForm = currentForm
                hasLoaded = true
                let team = try? await FamilyService.shared.getFamilyMembers(familyId: member.familyId)
                if let team { careTeam = team }
                return
            }
            needsFirstSave = false

            apply(loaded)
            // Snapshot from on-screen state (not the raw row) so formats match
            // exactly and an untouched form is never "changed".
            var snapshot = currentForm
            // A Custom row with no readable schedule sends nothing (dispatch
            // skips it), but apply() seeds editable times. Record what the
            // server really holds so those times show as unsaved: Save is
            // enabled and Back warns, instead of looking already scheduled.
            customScheduleMissing = loaded.scheduleType == .custom && loaded.customSchedule == nil
            if customScheduleMissing { snapshot.customSchedule = nil }
            loadedForm = snapshot
            hasLoaded = true

            // Rows saved by older iOS builds hold custom_schedule as a JSON
            // string, which dispatch can't read: no custom check-in was ever
            // sent. Rewrite it as an object now (00056 also repairs it
            // server-side; this covers a server without that migration).
            if loaded.customScheduleNeedsRepair, let schedule = loaded.customSchedule {
                var repair = ReceiverSettingsPatch()
                repair.set("custom_schedule", .schedule(schedule))
                try? await applyPatch(repair)
            }
        } catch {
            loadFailed = true
        }

        // Best effort: names for the escalation timeline, the owner's phone
        // for the text-alert status.
        if let team = try? await FamilyService.shared.getFamilyMembers(familyId: member.familyId) {
            careTeam = team
        }
    }

    /// Replace every field from the server row, so nothing from a previous
    /// state (or the defaults) survives a load.
    private func apply(_ loaded: ReceiverSettings) {
        settings = loaded

        checkinTime = Self.parseTime(loaded.checkinTime) ?? Calendar.current.date(from: DateComponents(hour: 8)) ?? checkinTime
        gracePeriod = loaded.gracePeriodMinutes
        reminderInterval = loaded.reminderIntervalMinutes
        escalationEnabled = loaded.escalationEnabled
        moodTrackingEnabled = loaded.moodTrackingEnabled
        smsEscalationEnabled = loaded.smsEscalationEnabled
        notifyOwnerOnCheckin = loaded.notifyOwnerOnCheckin
        receiverMode = loaded.receiverMode
        simpleMode = loaded.simpleMode
        audioConfirmationEnabled = loaded.audioConfirmationEnabled

        scheduleType = loaded.scheduleType
        schedulePaused = loaded.schedulePaused
        if let until = loaded.pausedUntil {
            pinPauseChoice(to: until)
        } else {
            pauseLength = .untilResumed
        }

        // Dispatch runs weekends at COALESCE(weekend_checkin_time, checkin_time).
        // Show that same time for a Weekday/Weekend row with no weekend time,
        // not an invented 10:00 the server would never use.
        if let weekend = loaded.weekendCheckinTime.flatMap(Self.parseTime) {
            weekendCheckinTime = weekend
        } else if loaded.scheduleType == .weekdayWeekend {
            weekendCheckinTime = checkinTime
        } else {
            weekendCheckinTime = Calendar.current.date(from: DateComponents(hour: 10)) ?? weekendCheckinTime
        }

        // Custom schedule: dual-read each day's times (multiTimes, falling
        // back to the legacy single field) via DaySchedule.times.
        dayTimes = [:]
        for day in DaySchedule.allDays { dayEnabled[day.key] = true }
        if let custom = loaded.customSchedule {
            for day in DaySchedule.allDays {
                let dates = custom.times(forDayKey: day.key).compactMap(Self.parseTime)
                dayEnabled[day.key] = !dates.isEmpty
                if !dates.isEmpty {
                    dayTimes[day.key] = dates.map { TimeEntry(time: $0) }
                }
            }
        }

        if let qStart = loaded.quietHoursStart.flatMap(Self.parseTime),
           let qEnd = loaded.quietHoursEnd.flatMap(Self.parseTime) {
            quietHoursEnabled = true
            quietHoursStart = qStart
            quietHoursEnd = qEnd
        } else {
            quietHoursEnabled = false
        }

        // A custom schedule with no per-day times gets editable pickers.
        if scheduleType == .custom { ensureCustomTimesPopulated() }
    }

    /// Show a pause end as "Until a date…" with that day selected. The
    /// receiver-calendar day is carried into the picker's calendar so it
    /// round-trips to the same instant.
    private func pinPauseChoice(to until: Date) {
        pauseLength = .onDate
        var noon = receiverCalendar.dateComponents([.year, .month, .day], from: until)
        noon.hour = 12
        pauseResumeDay = Calendar.current.date(from: noon) ?? until
    }

    /// Server "HH:mm:ss" or "HH:mm" → a Date on the picker's calendar.
    private static func parseTime(_ raw: String) -> Date? {
        guard let m = ReceiverSettingsForm.minutesOfDay(raw) else { return nil }
        return Calendar.current.date(from: DateComponents(hour: m / 60, minute: m % 60))
    }

    /// Ensure every enabled day has at least one editable check-in window when a
    /// custom schedule is active. Backs the DatePickers with real, stable state
    /// (keyed by TimeEntry.id) so edits persist.
    private func ensureCustomTimesPopulated(useWeekendTime: Bool = false) {
        for day in DaySchedule.allDays where (dayEnabled[day.key] ?? true) {
            if dayTimes[day.key]?.isEmpty ?? true {
                dayTimes[day.key] = [TimeEntry(time: seedTime(forDayKey: day.key, useWeekendTime: useWeekendTime))]
            }
        }
    }

    private struct IdRow: Decodable { let id: UUID }

    private enum SaveFailure: Error { case nothingUpdated }

    /// PATCH the row and confirm it was actually updated. RLS turns a write
    /// the caller may no longer make (ownership moved, member removed) into a
    /// silent 0-row success, which used to show "Settings saved".
    private func applyPatch(_ patch: ReceiverSettingsPatch) async throws {
        let rows: [IdRow] = try await SupabaseService.shared.client
            .from("receiver_settings")
            .update(patch)
            .eq("family_member_id", value: member.id.uuidString)
            .select("id")
            .execute()
            .value
        guard !rows.isEmpty else { throw SaveFailure.nothingUpdated }
    }

    /// Save goes to the existing row, or creates it when there is none yet.
    private func writePatch(_ patch: ReceiverSettingsPatch) async throws {
        if needsFirstSave {
            try await insertSettingsRow(patch)
        } else {
            try await applyPatch(patch)
        }
    }

    /// Create the missing row (owners may insert under "Owners can manage
    /// receiver settings"; the 00052 trigger fills in the receiver's zone). If
    /// a row appeared meanwhile (they re-joined), update that one instead.
    private func insertSettingsRow(_ patch: ReceiverSettingsPatch) async throws {
        var row = patch
        row.set("family_member_id", .string(member.id.uuidString))
        do {
            let rows: [IdRow] = try await SupabaseService.shared.client
                .from("receiver_settings")
                .insert(row)
                .select("id")
                .execute()
                .value
            guard !rows.isEmpty else { throw SaveFailure.nothingUpdated }
        } catch let error where "\(error)".contains("23505") {
            try await applyPatch(patch)
        }
    }

    /// PostgREST reports an unknown column as PGRST204 naming it.
    private static func isMissingColumn(_ error: Error, _ column: String) -> Bool {
        let text = "\(error) \(error.localizedDescription)"
        return text.contains(column)
    }

    /// Returns true when everything was saved.
    @discardableResult
    private func saveSettings() async -> Bool {
        guard !isSaving else { return false }

        // A custom schedule with every day off persists an empty schedule: the
        // receiver silently never gets a check-in request.
        if scheduleType == .custom,
           !DaySchedule.allDays.contains(where: { dayEnabled[$0.key] ?? false }) {
            validationMessage = String(localized: "Turn on at least one day — otherwise \(name) will never get a check-in request.")
            DailyOKHaptics.error()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Select at least one check-in day"))
            return false
        }
        if quietHoursEnabled && !quietHoursValid {
            validationMessage = String(localized: "Quiet hours need different start and end times.")
            DailyOKHaptics.error()
            return false
        }
        // Dispatch sends nothing during quiet hours, so a check-in timed inside
        // them is not asked (and never escalates) — block it.
        if !quietHourConflicts.isEmpty {
            validationMessage = quietConflictText
            DailyOKHaptics.error()
            UIAccessibility.post(notification: .announcement, argument: quietConflictText)
            return false
        }

        let form = currentForm
        // A first save sends every field, so the new row holds what is on
        // screen rather than column defaults.
        var patch = form.patch(from: needsFirstSave ? nil : loadedForm)
        guard !patch.isEmpty else {
            loadedForm = form
            return true
        }

        isSaving = true
        defer { isSaving = false }

        var pauseEndUnsupported = false
        do {
            do {
                try await writePatch(patch)
            } catch {
                // Server without 00056: save everything else and say that the
                // pause won't end by itself.
                guard patch["paused_until"] != nil, Self.isMissingColumn(error, "paused_until") else { throw error }
                patch.remove("paused_until")
                if !patch.isEmpty { try await writePatch(patch) }
                pauseEndUnsupported = true
            }

            if pauseEndUnsupported {
                pauseLength = .untilResumed
                saveNote = String(localized: "Check-ins for \(name) are paused, but they can't resume by themselves yet. Turn Pause off here when you're ready.")
            } else if schedulePaused, let saved = form.pausedUntil, pauseLength != .onDate {
                // Pin a relative choice ("For 3 days") to the date just saved,
                // so it doesn't drift — and read as unsaved — tomorrow.
                pinPauseChoice(to: saved)
            }
            loadedForm = currentForm
            customScheduleMissing = false
            needsFirstSave = false

            // Confirm the save for sighted, haptic, AND VoiceOver users.
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Settings saved"))
            if reduceMotion {
                showSavedConfirmation = true
            } else {
                withAnimation { showSavedConfirmation = true }
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if reduceMotion {
                    showSavedConfirmation = false
                } else {
                    withAnimation { showSavedConfirmation = false }
                }
            }
            return true
        } catch SaveFailure.nothingUpdated {
            errorTitle = String(localized: "Couldn't save")
            errorMessage = String(localized: "Nothing was changed — you may no longer manage \(name)'s settings. Go back to the Family tab and refresh.")
        } catch {
            errorTitle = String(localized: "Couldn't save")
            errorMessage = DailyOKError.network(error).localizedDescription
        }
        DailyOKHaptics.error()
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Couldn't save settings"))
        return false
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
            let times = (dayTimes[day.key] ?? [TimeEntry(time: seedTime(forDayKey: day.key))])
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
}
