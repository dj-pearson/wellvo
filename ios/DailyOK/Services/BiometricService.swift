import LocalAuthentication

actor BiometricService {
    static let shared = BiometricService()

    private let biometricEnabledKey = "biometric_auth_enabled"
    private let biometricSkippedKey = "biometric_auth_skipped"

    // MARK: - Availability

    /// Check if biometric authentication (Face ID / Touch ID) is available on this device.
    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Returns the type of biometric available (faceID, touchID, or none).
    func biometricType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    /// Human-readable name for the available biometric type.
    func biometricName() -> String {
        switch biometricType() {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biometric"
        }
    }

    // MARK: - Authentication

    /// Prompt user for authentication. Returns true if successful.
    ///
    /// Uses `.deviceOwnerAuthentication` (not `…WithBiometrics`) so the system
    /// falls back to the device passcode automatically: the "Use Passcode"
    /// affordance actually works, and a biometric lockout (too many failed Face
    /// ID attempts) can't permanently strand the user out of the app (US-IOS108).
    func authenticate(reason: String = "Unlock Daily OK") async -> Bool {
        let context = LAContext()

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }

    // MARK: - Preference Management

    /// Whether the user has enabled biometric unlock.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: biometricEnabledKey) }
    }

    /// Enable or disable biometric auth preference.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: biometricEnabledKey)
    }

    /// Whether the user has already been asked about biometric and declined/skipped.
    var hasBeenSkipped: Bool {
        get { UserDefaults.standard.bool(forKey: biometricSkippedKey) }
    }

    func setSkipped(_ skipped: Bool) {
        UserDefaults.standard.set(skipped, forKey: biometricSkippedKey)
    }

    /// Whether we should prompt the user to enable biometric (first time after sign-in).
    func shouldPromptToEnable() -> Bool {
        return isBiometricAvailable() && !isEnabled && !hasBeenSkipped
    }

    /// Reset biometric preferences (on sign-out).
    func reset() {
        UserDefaults.standard.removeObject(forKey: biometricEnabledKey)
        UserDefaults.standard.removeObject(forKey: biometricSkippedKey)
    }
}
