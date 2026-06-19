import Foundation
import SwiftData
import UserNotifications

/// Handles the renewal notification's action buttons ("Mark as used", "Snooze") off the
/// main flow. Holds the app's shared `ModelContainer` — set once at launch via
/// ``configure(container:)`` — so it can record usage or schedule a snooze without a view
/// in scope.
@MainActor
public final class NotificationActionHandler {
    public static let shared = NotificationActionHandler()

    private var container: ModelContainer?

    private init() {}

    /// Call once at launch with the app's shared container (e.g. from `DriftApp`).
    public func configure(container: ModelContainer) {
        self.container = container
    }

    /// "Mark as used": log a usage record and bump `lastUsedDate`. This also feeds the AI
    /// review's "days since last use" signal, so the next monthly review reflects it.
    public func recordUsage(subscriptionID: UUID) async {
        guard let container else { return }
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        guard let sub = all.first(where: { $0.id == subscriptionID }) else { return }

        let record = UsageRecord(subscription: sub, wasUsed: true)
        record.subscriptionID = sub.id   // point the CloudKit backup link at the parent
        context.insert(record)
        sub.lastUsedDate = Date()
        try? context.save()
    }

    /// "Snooze 1 day": fire one more reminder `days` later. Uses a `snooze-` identifier
    /// outside the `renewal-` namespace, so a full reschedule won't wipe it. Re-snoozing
    /// the same subscription replaces the pending snooze (same identifier).
    public func snooze(subscriptionID: UUID, by days: Int) async {
        guard let container else { return }
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        guard let sub = all.first(where: { $0.id == subscriptionID }) else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(sub.name) renews soon"
        let formatted = ExchangeRates.format(sub.monthlyCost, currencyCode: sub.currencyCode)
        content.body = "\(formatted) on \(sub.nextRenewalDate.formatted(date: .abbreviated, time: .omitted))."
        content.sound = .default
        content.categoryIdentifier = "drift.renewal"
        content.userInfo = [
            "subscriptionID": sub.id.uuidString,
            "kind": "renewal"
        ]

        let interval = TimeInterval(max(1, days) * 24 * 60 * 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "snooze-\(sub.id.uuidString)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
