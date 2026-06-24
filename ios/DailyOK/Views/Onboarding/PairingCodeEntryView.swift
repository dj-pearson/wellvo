import SwiftUI

/// Allows a receiver to enter a 6-digit pairing code from their SMS
/// to bind this device (typically an iPad) to the family.
struct PairingCodeEntryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var joinedSuccessfully = false
    @State private var checkinTimeDisplay = "8:00 AM"
    // Persist attempt/lockout state so backing out and reopening the screen can't
    // reset the 10-attempt / 15-minute lockout (matches AuthViewModel's approach).
    @AppStorage("dailyok.pairing.failedAttempts") private var failedAttempts = 0
    @AppStorage("dailyok.pairing.lockoutUntil") private var lockoutUntilEpoch: Double = 0

    private var lockoutUntil: Date? {
        lockoutUntilEpoch > 0 ? Date(timeIntervalSince1970: lockoutUntilEpoch) : nil
    }
    private var isLockedOut: Bool {
        if let until = lockoutUntil { return Date() < until }
        return false
    }

    var body: some View {
        ZStack {
            AmbientBackground(tone: joinedSuccessfully ? .calm : .neutral)

            VStack(spacing: 0) {
                // Back button on glass pill
                HStack {
                    Button {
                        appState.showPairingCodeEntry = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DailyOKColor.green700)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassPill(style: .ultraThin)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

                if joinedSuccessfully {
                    successView
                } else {
                    codeEntryView
                }

                Spacer()
            }
        }
    }

    // MARK: - Code Entry

    private var codeEntryView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.teal.opacity(0.4))
                    .frame(width: 120, height: 120)
                    .blur(radius: 28)
                Image(systemName: "ipad.and.iphone")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(colors: [DailyOKColor.green500, DailyOKColor.teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            Text("Set Up This Device")
                .font(.largeTitle)
                .fontWeight(.bold)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("Enter the 6-digit code from the text message you received on your phone.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.horizontal, 32)

            SegmentedCodeField(code: $code, length: 6, onComplete: {
                Task { await submitCode() }
            }, autoFocus: !isLockedOut)
            .disabled(isLockedOut || isSubmitting)

            Text("\(code.count) of 6")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await submitCode() }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Text("Join Family")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green500)
            .controlSize(.large)
            .disabled(code.count != 6 || isSubmitting || isLockedOut)
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .glassCard(style: .regular, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .padding(.horizontal, 24)
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.green300.opacity(0.5))
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(colors: [DailyOKColor.green400, DailyOKColor.green600],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.bounce, value: joinedSuccessfully)
            }

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("Your daily check-in is at **\(checkinTimeDisplay)**.\nJust tap \"I'm OK\" when you get the notification.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.horizontal, 32)

            Button("Start Checking In") {
                appState.showPairingCodeEntry = false
                appState.isOnboarding = false
                appState.currentUserRole = .receiver
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green500)
            .controlSize(.large)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .glassCard(style: .regular, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .padding(.horizontal, 24)
    }

    // MARK: - Submit

    private func submitCode() async {
        guard code.count == 6, !isSubmitting else { return }

        // Honor an active, persisted lockout.
        if let lockoutEnd = lockoutUntil, Date() < lockoutEnd {
            let remaining = Int(lockoutEnd.timeIntervalSinceNow / 60) + 1
            errorMessage = "Too many failed attempts. Try again in \(remaining) minute\(remaining == 1 ? "" : "s")."
            return
        }
        // A lapsed lockout resets the counter for a fresh run of attempts.
        if lockoutUntilEpoch > 0 {
            lockoutUntilEpoch = 0
            failedAttempts = 0
        }

        // Set the submitting state BEFORE the backoff sleep so the spinner shows
        // during the wait — otherwise the tap looks ignored and gets mashed.
        isSubmitting = true
        errorMessage = nil

        // Exponential backoff delay between attempts.
        if failedAttempts > 0 {
            let delay = min(pow(2.0, Double(failedAttempts - 1)), 16.0)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        do {
            let response = try await FamilyService.shared.redeemPairingCode(code)

            if let error = response.error {
                failedAttempts += 1
                if failedAttempts >= 10 {
                    lockoutUntilEpoch = Date().addingTimeInterval(15 * 60).timeIntervalSince1970
                    errorMessage = "Too many failed attempts. Try again in 15 minutes."
                } else {
                    errorMessage = "\(error) (\(10 - failedAttempts) attempts remaining)"
                }
            } else if response.success == true {
                failedAttempts = 0
                lockoutUntilEpoch = 0
                if let time = response.checkinTime {
                    checkinTimeDisplay = formatCheckinTime(time)
                }
                if reduceMotion {
                    joinedSuccessfully = true
                } else {
                    withAnimation { joinedSuccessfully = true }
                }
            } else {
                errorMessage = "Something went wrong. Please try again."
            }
        } catch {
            errorMessage = "Could not connect. Please check your internet and try again."
        }

        isSubmitting = false
    }

    private func formatCheckinTime(_ time: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let date = formatter.date(from: time) else { return time }
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
