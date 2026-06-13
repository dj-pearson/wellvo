import Foundation
import AVFoundation
import UIKit

/// Spoken/audible confirmation for low-vision receivers (US-IOS012). Only used
/// on a *confirmed online* check-in — never for an optimistic offline queue,
/// since that isn't confirmed yet. Skips speech when VoiceOver is already
/// running so we don't double-speak.
enum CheckInAudio {
    private static let synthesizer = AVSpeechSynthesizer()

    /// Speak a short reassurance. No-op if VoiceOver is active (it already
    /// announces the state change via the view's accessibility label).
    static func confirm(_ message: String = "You're all set. Your family has been notified.") {
        guard !UIAccessibility.isVoiceOverRunning else { return }

        // Use a non-mixing, ducking session briefly so the phrase is audible
        // even with other audio playing, then deactivate.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
        synthesizer.speak(utterance)

        // Release the session shortly after the phrase would have finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}
