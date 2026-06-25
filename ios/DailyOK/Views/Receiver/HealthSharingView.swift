import SwiftUI

/// US-IOS017 — receiver-facing opt-in for sharing a passive "active today"
/// signal derived from Apple Health. Privacy-first: explains exactly what is
/// shared (a yes/no, never raw data), default off, revocable any time.
struct HealthSharingView: View {
    @StateObject private var health = HealthService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { health.isSharingEnabled },
                        set: { newValue in
                            isWorking = true
                            Task {
                                let ok = await health.setSharing(newValue)
                                isWorking = false
                                // Enabling failed (permission denied) — explain
                                // instead of letting the toggle silently revert
                                // (US-IOS111).
                                if newValue && !ok { showPermissionAlert = true }
                            }
                        }
                    )) {
                        Label("Share activity", systemImage: "figure.walk")
                    }
                    .tint(DailyOKColor.green500)
                    .disabled(isWorking || !health.isHealthDataAvailable)
                } footer: {
                    if !health.isHealthDataAvailable {
                        Text("Apple Health isn't available on this device.")
                    } else {
                        Text("When on, your family can see a simple “Active today” note alongside your check-ins.")
                    }
                }

                Section("What your family sees") {
                    bullet("figure.walk", "Just a yes/no: whether you've moved around today.")
                    bullet("checkmark.shield.fill", "Your steps, workouts, and any other health details never leave your phone.")
                    bullet("hand.raised.fill", "This never replaces your check-in — it's only an extra bit of reassurance.")
                    bullet("xmark.circle.fill", "Turn this off any time and what you shared is removed.")
                }

                Section {
                    Text("Daily OK is not a medical device. This is gentle reassurance for your family — it does not monitor your health and does not detect falls or emergencies.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activity Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isWorking { ProgressView() }
            }
            .alert("Couldn't Enable Activity Sharing", isPresented: $showPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Daily OK needs permission to read your step count. You can grant it in the Health app under Sharing → Apps.")
            }
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(DailyOKColor.green)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
