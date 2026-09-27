import SwiftUI
import UserNotifications

/// Joining a family with the 6-digit setup code from an invite text — on any
/// device, and the main path for anyone who signed in with Apple or email.
///
/// The code is checked first and the family described ("Join Sarah's
/// family?"); only "Join" redeems it. A mistyped code that happened to match
/// another family's invite used to join that stranger's family on the sixth
/// digit. After joining, the person is asked for notification permission —
/// this path never asked, so no reminder ever arrived.
struct PairingCodeEntryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var joinedSuccessfully = false
    /// The role the server says this code joined as (a co-caregiver code
    /// makes a viewer, who is never asked to check in).
    @State private var joinedRole: UserRole = .receiver
    // nil until the server tells us the real time — never assert a fabricated
    // "8:00 AM" the receiver might not actually be scheduled for (US-IOS112).
    @State private var checkinTimeDisplay: String?
    /// The family the code belongs to, before joining.
    @State private var preview: JoinPreview?
    @State private var ownerName: String?
    /// After joining: asking for notification permission.
    @State private var askingForNotifications = false
    @State private var notificationDenied = false
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
                // Back is only for leaving BEFORE joining. After a join it used
                // to drop a new member on "How will you use it?" as if nothing
                // had happened (re-entering the used code then failed).
                HStack {
                    if !joinedSuccessfully {
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
                        .disabled(isSubmitting)
                    }
                    Spacer()
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 24)
                .padding(.top, 12)

                ScrollView {
                    VStack {
                        if askingForNotifications {
                            NotificationPermissionStepCard(
                                isCaregiver: joinedRole == .viewer,
                                denied: $notificationDenied,
                                onFinished: { finish() }
                            )
                            .padding(.horizontal, 24)
                        } else if joinedSuccessfully {
                            successView
                        } else if let preview {
                            JoinConsentCard(
                                preview: preview,
                                isProcessing: isSubmitting,
                                errorMessage: errorMessage,
                                onJoin: { Task { await confirmJoin() } },
                                onDecline: { declinePreview() },
                                declineTitle: "Not the right family"
                            )
                            .padding(.horizontal, 24)
                        } else {
                            codeEntryView
                        }
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .onAppear {
            // A lockout still running from before used to show only disabled
            // boxes, with no word of why or for how long.
            if let until = lockoutUntil, Date() < until {
                errorMessage = Self.lockoutMessage(until: until)
            }
        }
    }

    nonisolated static func lockoutMessage(until: Date, now: Date = Date()) -> String {
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        return String(localized: "Too many tries. You can try again in \(minutes) minute\(minutes == 1 ? "" : "s"). If the code keeps failing, ask the person who invited you to send a new one.")
    }

    // MARK: - Code Entry

    private var codeEntryView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DailyOKColor.teal.opacity(0.4))
                    .frame(width: 120, height: 120)
                    .blur(radius: 28)
                Image(systemName: "number.square.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(colors: [DailyOKColor.green500, DailyOKColor.teal],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            .accessibilityHidden(true)

            Text("Enter your setup code")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityAddTraits(.isHeader)

            Text("Type the 6-digit code from the invite text you received. We'll show you whose family it is before you join.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.horizontal, 16)

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
                    .font(.callout)
                    .foregroundStyle(DailyOKColor.error)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await submitCode() }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green700)
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
            .accessibilityHidden(true)

            Text(ownerName.map { String(localized: "You joined \($0)'s family") } ?? String(localized: "You're All Set!"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Group {
                if joinedRole == .viewer {
                    Text("You're a co-caregiver now. We'll tell you if a check-in is missed — you won't be asked to check in yourself.")
                } else if joinedRole == .owner {
                    Text("This is your own family's code. You're already its owner.")
                } else {
                    Text(checkinTimeDisplay.map { "Your daily check-in is at **\($0)**.\nJust tap \"I'm OK\" when you get the notification." }
                         ?? "We'll remind you each day.\nJust tap \"I'm OK\" when you get the notification.")
                }
            }
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.horizontal, 32)

            Button(joinedRole == .receiver ? "Start Checking In" : "Open Daily OK") {
                Task { await continueAfterJoin() }
            }
            .buttonStyle(.borderedProminent)
            .tint(DailyOKColor.green700)
            .controlSize(.large)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .glassCard(style: .regular, radius: DailyOKGlass.radiusLarge, elevation: DailyOKElevation.level3)
        .padding(.horizontal, 24)
    }

    /// Ask for notifications unless they are already on (or this is an owner
    /// who typed their own code), then open the app.
    private func continueAfterJoin() async {
        guard joinedRole != .owner else { finish(); return }
        let status = await PushNotificationService.shared.checkPermissionStatus()
        if status == .authorized {
            finish()
        } else {
            notificationDenied = status == .denied
            if reduceMotion {
                askingForNotifications = true
            } else {
                withAnimation { askingForNotifications = true }
            }
        }
    }

    private func finish() {
        appState.showPairingCodeEntry = false
        appState.isOnboarding = false
        appState.currentUserRole = joinedRole
    }

    // MARK: - Submit

    /// Check the code and describe its family (nothing is joined yet).
    private func submitCode() async {
        guard code.count == 6, !isSubmitting else { return }

        // Honor an active, persisted lockout.
        if let lockoutEnd = lockoutUntil, Date() < lockoutEnd {
            errorMessage = Self.lockoutMessage(until: lockoutEnd)
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

        // The submit runs on a Task not tied to this view's lifecycle, and the
        // backoff above can sleep up to 16s. If the user tapped Back during the
        // wait (or the request below), don't submit or mutate the persisted
        // attempt/lockout state for a screen they've already left.
        guard appState.showPairingCodeEntry else {
            isSubmitting = false
            return
        }

        do {
            let response = try await FamilyService.shared.previewPairingCode(code)
            guard appState.showPairingCodeEntry else {
                isSubmitting = false
                return
            }
            handle(response)
        } catch {
            handle(error)
        }

        isSubmitting = false
    }

    /// "Join" on the consent card.
    private func confirmJoin() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let response = try await FamilyService.shared.redeemPairingCode(code)
            guard appState.showPairingCodeEntry else {
                isSubmitting = false
                return
            }
            handle(response)
        } catch let error as EdgeFunctionsClient.HTTPError where error.status == 400 {
            // Taken or expired since the preview; or it DID join and only the
            // answer was lost. Ask the server before calling it a failure.
            if let role = try? await FamilyService.shared.getCurrentUserRole(), role != .owner {
                markJoined(role: role, checkinTime: preview?.checkinTime, owner: preview?.ownerName)
            } else {
                errorMessage = error.serverMessage
                    ?? String(localized: "That code can't be used any more. Ask for a new invite.")
            }
        } catch {
            handle(error)
        }
        isSubmitting = false
    }

    private func declinePreview() {
        preview = nil
        code = ""
        errorMessage = nil
    }

    private func handle(_ response: RedeemCodeResponse) {
        if let described = response.joinPreview {
            failedAttempts = 0
            lockoutUntilEpoch = 0
            if described.alreadyMember {
                markJoined(role: response.joinedRole, checkinTime: described.checkinTime, owner: described.ownerName)
            } else {
                preview = described
            }
        } else if let error = response.error {
            recordFailure(serverMessage: error, attemptsRemaining: nil)
        } else if response.success == true {
            // A redeem (or a server that predates previews and joined at once).
            failedAttempts = 0
            lockoutUntilEpoch = 0
            markJoined(role: response.joinedRole,
                       checkinTime: response.checkinTime ?? preview?.checkinTime,
                       owner: response.ownerName ?? preview?.ownerName)
        } else {
            errorMessage = String(localized: "Something went wrong. Please try again.")
        }
    }

    private func handle(_ error: Error) {
        guard appState.showPairingCodeEntry else { return }
        if let http = error as? EdgeFunctionsClient.HTTPError {
            // The server answered. Every non-2xx used to read "Could not
            // connect", so a mistyped code looked like a network fault.
            switch http.status {
            case 429:
                // Server-side lockout (durable, per user / per IP). Mirror it.
                let wait = http.retryAfter ?? 15 * 60
                let until = Date().addingTimeInterval(wait)
                lockoutUntilEpoch = until.timeIntervalSince1970
                errorMessage = Self.lockoutMessage(until: until)
            case 400:
                recordFailure(serverMessage: http.serverMessage, attemptsRemaining: Self.attemptsRemaining(in: http.body))
            default:
                // e.g. 403 "This family has no free receiver slots…" — not the
                // receiver's typing, so it doesn't count as an attempt.
                errorMessage = http.serverMessage
                    ?? String(localized: "Something went wrong. Please try again.")
            }
        } else {
            errorMessage = String(localized: "Could not connect. Please check your internet and try again.")
        }
    }

    private func recordFailure(serverMessage: String?, attemptsRemaining: Int?) {
        failedAttempts += 1
        let remaining = attemptsRemaining ?? max(0, 10 - failedAttempts)
        if failedAttempts >= 10 || remaining == 0 {
            let until = Date().addingTimeInterval(15 * 60)
            lockoutUntilEpoch = until.timeIntervalSince1970
            errorMessage = Self.lockoutMessage(until: until)
        } else {
            let base = serverMessage ?? String(localized: "That code didn't work. Check it and try again.")
            errorMessage = String(localized: "\(base) (\(remaining) tries left)")
        }
        code = ""
    }

    /// `attemptsRemaining` from a 400 body, when the server sent it.
    nonisolated static func attemptsRemaining(in body: String) -> Int? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["attemptsRemaining"] as? Int
    }

    private func markJoined(role: UserRole, checkinTime: String?, owner: String?) {
        joinedRole = role
        if let time = checkinTime {
            checkinTimeDisplay = formatCheckinTimeForDisplay(time)
        }
        ownerName = JoinPreview.presentableName(owner)
        preview = nil
        errorMessage = nil
        if reduceMotion {
            joinedSuccessfully = true
        } else {
            withAnimation { joinedSuccessfully = true }
        }
    }
}
