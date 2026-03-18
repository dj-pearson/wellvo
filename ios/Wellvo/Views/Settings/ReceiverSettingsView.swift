import SwiftUI
import Supabase

struct ReceiverSettingsView: View {
    let member: FamilyMember

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

    private let gracePeriodOptions = [15, 30, 45, 60, 90, 120]

    var body: some View {
        Form {
            // Check-In Schedule
            Section {
                DatePicker("Daily Check-In Time", selection: $checkinTime, displayedComponents: .hourAndMinute)

                // Timezone display
                HStack {
                    Text("Timezone")
                    Spacer()
                    Text(member.user?.timezone ?? TimeZone.current.identifier)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Check-In Schedule")
            } footer: {
                Text("A push notification will be sent at this time every day.")
            }

            // Escalation Chain
            Section {
                Toggle("Escalation Alerts", isOn: $escalationEnabled)

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
            } header: {
                Text("SMS Escalation")
            } footer: {
                Text("Send an SMS to you and viewers if push notifications fail during escalation. Requires a phone number on your account.")
            }

            // Mood Tracking
            Section {
                Toggle("Mood Tracking", isOn: $moodTrackingEnabled)
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
            }
        }
        .task { await loadSettings() }
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

            if let qStart = loaded.quietHoursStart, let qEnd = loaded.quietHoursEnd {
                quietHoursEnabled = true
                if let start = formatter.date(from: qStart) { quietHoursStart = start }
                if let end = formatter.date(from: qEnd) { quietHoursEnd = end }
            }
        } catch {
            print("Failed to load receiver settings: \(error)")
        }
        isLoading = false
    }

    private func saveSettings() async {
        isSaving = true

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: checkinTime)

        var updates: [String: String] = [
            "checkin_time": timeString,
            "grace_period_minutes": String(gracePeriod),
            "reminder_interval_minutes": String(reminderInterval),
            "escalation_enabled": String(escalationEnabled),
            "mood_tracking_enabled": String(moodTrackingEnabled),
            "sms_escalation_enabled": String(smsEscalationEnabled),
        ]

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

            withAnimation { showSavedConfirmation = true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showSavedConfirmation = false }
        } catch {
            print("Failed to save settings: \(error)")
        }

        isSaving = false
    }
}
