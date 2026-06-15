import AppIntents

/// Surfaces Drift's intents to Siri and the Shortcuts app with spoken phrases.
/// Call `DriftAppShortcuts.updateAppShortcutParameters()` from the app after the
/// subscription set changes, so the "mark as used" phrase knows current names.
struct DriftAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MonthlySpendIntent(),
            phrases: [
                "What's my total in \(.applicationName)",
                "Show my monthly spend in \(.applicationName)",
                "\(.applicationName) monthly total"
            ],
            shortTitle: "Monthly total",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: AddSubscriptionIntent(),
            phrases: [
                "Add a subscription to \(.applicationName)",
                "Track a new subscription in \(.applicationName)"
            ],
            shortTitle: "Add subscription",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: MarkSubscriptionUsedIntent(),
            phrases: [
                "Mark \(\.$subscription) as used in \(.applicationName)",
                "Log usage for \(\.$subscription) in \(.applicationName)"
            ],
            shortTitle: "Mark as used",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: RunMonthlyReviewIntent(),
            phrases: [
                "What should I review this month in \(.applicationName)",
                "Run my \(.applicationName) review"
            ],
            shortTitle: "Monthly review",
            systemImageName: "sparkles"
        )
    }
}
