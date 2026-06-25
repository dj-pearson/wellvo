import AppIntents

/// Exposes the check-in intent to Siri and the Shortcuts app with natural
/// phrases so receivers — especially those with low vision or limited
/// dexterity — can check in hands-free ("Hey Siri, check in with Daily OK").
/// Discovered automatically by the system; no registration code required.
@available(iOS 16.0, watchOS 9.0, *)
struct DailyOKAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckInIntent(source: "siri"),
            phrases: [
                "Check in with \(.applicationName)",
                "I'm OK with \(.applicationName)",
                "\(.applicationName) check in",
                "Tell \(.applicationName) I'm okay",
            ],
            shortTitle: "Check In",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
