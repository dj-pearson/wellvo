import SwiftUI
import os

/// US-IOS014 — owner-configurable daily / weekly digest.
///
/// Stores the preference on the `users` row (digest_frequency / digest_hour).
/// The actual send is handled server-side by the `dispatch-caregiver-digests`
/// pg_cron job + `/send-digest` edge function; this screen only edits the
/// preference. The in-app summary lives on the dashboard's weekly-summary card.
struct CaregiverDigestView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var frequency: String = "off"
    @State private var hour: Int = 8
    @State private var isLoading = true
    @State private var isSaving = false
    /// What the server has. Save is offered only for a real change, and a
    /// foreground reload never overwrites a choice not yet saved.
    @State private var loaded: (frequency: String, hour: Int)?
    @State private var showSaved = false
    @State private var errorMessage: String?
    /// True when the current preference couldn't be read. Saving is blocked while
    /// set so a failed load can't overwrite the real server value with defaults.
    @State private var loadFailed = false

    private struct DigestPrefs: Encodable {
        let digest_frequency: String
        let digest_hour: Int
    }

    private struct DigestRow: Decodable {
        let digestFrequency: String?
        let digestHour: Int?
        enum CodingKeys: String, CodingKey {
            case digestFrequency = "digest_frequency"
            case digestHour = "digest_hour"
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Summary", selection: $frequency) {
                    Text("Off").tag("off")
                    Text("Daily").tag("daily")
                    Text("Weekly").tag("weekly")
                }
            } footer: {
                Text("A notification summarising your family's check-ins — how many came in, any misses, and how everyone's been feeling. Weekly summaries arrive on Mondays.")
            }

            if frequency != "off" {
                Section {
                    Picker("Delivery time", selection: $hour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(Self.hourLabel(h)).tag(h)
                        }
                    }
                } footer: {
                    Text("Delivered around this time in your timezone. The summary only sends if you've allowed notifications.")
                }
            }

            if loadFailed {
                Section {
                    Label("Couldn't load your current summary setting. Saving is turned off so it isn't overwritten.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DailyOKColor.warning)
                    Button("Retry") {
                        Task { await load() }
                    }
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Save")
                        Spacer()
                        if isSaving { ProgressView() }
                    }
                }
                .disabled(isLoading || loadFailed || isSaving || !isDirty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(tone: .neutral))
        .navigationTitle("Check-in Summary")
        .overlay {
            if showSaved {
                Text("Saved")
                    .font(.headline)
                    .padding()
                    .background(DailyOKColor.green700, in: Capsule())
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true) // announced via UIAccessibility.post
            }
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await load() }
        // Reload on foreground so a stale value isn't re-saved (US-IOS111) —
        // but not over an unsaved choice.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, !isDirty { Task { await load() } }
        }
    }

    private var isDirty: Bool {
        guard let loaded else { return false }
        return loaded.frequency != frequency || (frequency != "off" && loaded.hour != hour)
    }

    private static func hourLabel(_ h: Int) -> String {
        var comps = DateComponents()
        comps.hour = h
        comps.minute = 0
        let cal = Calendar.current
        if let date = cal.date(from: comps) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return "\(h):00"
    }

    private func load() async {
        loadFailed = false
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            // No session: treat like a failed load so Save can't write defaults
            // (it used to be enabled and then silently do nothing).
            loadFailed = true
            isLoading = false
            return
        }
        do {
            let row: DigestRow = try await SupabaseService.shared.client
                .from("users")
                .select("digest_frequency, digest_hour")
                .eq("id", value: session.user.id.uuidString)
                .single()
                .execute()
                .value
            frequency = row.digestFrequency ?? "off"
            hour = row.digestHour ?? 8
            loaded = (frequency, hour)
        } catch {
            // Couldn't read the current preference (network blip / RLS). Do NOT
            // silently fall back to defaults and leave Save enabled — a Save
            // would overwrite the real value (e.g. "daily") with "off". Flag it,
            // block Save, and offer Retry (mirrors DataRetentionView, US-IOS111).
            Log.settings.error("Failed to load digest prefs: \(error.localizedDescription, privacy: .public)")
            loadFailed = true
        }
        isLoading = false
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        guard let session = try? await SupabaseService.shared.client.auth.session else {
            errorMessage = String(localized: "You're signed out. Sign in again to change your summary.")
            return
        }
        do {
            try await SupabaseService.shared.client
                .from("users")
                .update(DigestPrefs(digest_frequency: frequency, digest_hour: hour), returning: .minimal)
                .eq("id", value: session.user.id.uuidString)
                .execute()

            loaded = (frequency, hour)
            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Summary settings saved"))
            withAnimation { showSaved = true }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSaved = false }
        } catch {
            Log.settings.error("Failed to save digest prefs: \(error.localizedDescription, privacy: .public)")
            DailyOKHaptics.error()
            errorMessage = AccountCopy.failureMessage(for: error, action: String(localized: "save your summary setting"))
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Couldn't save digest settings"))
        }
    }
}
