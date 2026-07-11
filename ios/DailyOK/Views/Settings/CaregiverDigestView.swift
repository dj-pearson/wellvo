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
                Text("A gentle summary of your family's check-ins — consistency, streaks, any misses, and how everyone's been feeling. Weekly summaries arrive on Mondays.")
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
                Button("Save") {
                    Task { await save() }
                }
                .disabled(isLoading || loadFailed)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(tone: .neutral))
        .navigationTitle("Daily Summary")
        .overlay {
            if showSaved {
                Text("Saved")
                    .font(.headline)
                    .padding()
                    .background(.green, in: Capsule())
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
        // Reload on foreground so a stale value isn't re-saved (US-IOS111).
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await load() } }
        }
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
        guard let session = try? await SupabaseService.shared.client.auth.session else { return }
        do {
            try await SupabaseService.shared.client
                .from("users")
                .update(DigestPrefs(digest_frequency: frequency, digest_hour: hour))
                .eq("id", value: session.user.id.uuidString)
                .execute()

            DailyOKHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Digest settings saved"))
            withAnimation { showSaved = true }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSaved = false }
        } catch {
            Log.settings.error("Failed to save digest prefs: \(error.localizedDescription, privacy: .public)")
            DailyOKHaptics.error()
            errorMessage = DailyOKError.network(error).localizedDescription
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Couldn't save digest settings"))
        }
    }
}
