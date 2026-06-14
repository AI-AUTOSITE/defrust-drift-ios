import Foundation

/// A subscription's desired renewal reminders — input to ``NotificationPlanner``.
///
/// Framework-free and `nonisolated` (the project builds with main-actor-by-default
/// isolation) so planning runs on any executor and is unit-testable directly. The
/// `@MainActor` scheduler builds these from SwiftData `Subscription`s.
nonisolated struct SubscriptionNotificationRequest: Sendable, Hashable {
    let subscriptionID: UUID
    let subscriptionName: String
    let renewalDate: Date
    let isPaused: Bool
    /// Enabled "days before renewal" reminders, e.g. `[1, 3, 7]`.
    let daysBeforeOptions: [Int]

    init(
        subscriptionID: UUID,
        subscriptionName: String,
        renewalDate: Date,
        isPaused: Bool = false,
        daysBeforeOptions: [Int]
    ) {
        self.subscriptionID = subscriptionID
        self.subscriptionName = subscriptionName
        self.renewalDate = renewalDate
        self.isPaused = isPaused
        self.daysBeforeOptions = daysBeforeOptions
    }
}

/// One concrete local notification the app intends to schedule.
nonisolated struct PlannedNotification: Sendable, Hashable, Identifiable {
    let subscriptionID: UUID
    let subscriptionName: String
    let daysBeforeRenewal: Int
    let fireDate: Date

    /// Stable identifier shared with the eventual `UNNotificationRequest` so the
    /// scheduler can add and later cancel the exact notification
    /// (`renewal-<uuid>-<daysBefore>`, matching Part 1B §9.4/§9.5).
    var id: String { "renewal-\(subscriptionID.uuidString)-\(daysBeforeRenewal)" }
}

/// Pure planning for renewal notifications.
///
/// iOS silently drops pending local notifications beyond a system cap of **64**
/// (Apple Developer Forums thread 811171; reproduced in the field), so Drift
/// schedules only the soonest `limit` notifications and reschedules as renewals
/// pass. Everything here is deterministic and side-effect-free; the
/// `UNUserNotificationCenter` I/O lives in the `@MainActor` scheduler that calls it.
nonisolated enum NotificationPlanner {

    /// iOS's effective cap on simultaneously-pending local notifications.
    static let systemPendingLimit = 64

    /// Fire date for a reminder `daysBeforeRenewal` ahead of `renewalDate`.
    /// Returns `nil` when that moment is not strictly in the future relative to `now`.
    static func fireDate(
        renewalDate: Date,
        daysBeforeRenewal: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let candidate = calendar.date(byAdding: .day, value: -daysBeforeRenewal, to: renewalDate),
              candidate > now
        else { return nil }
        return candidate
    }

    /// Expand requests into individual notifications, drop paused/past ones, and
    /// keep only the soonest `limit`. Ties (identical fire dates) break by name then
    /// days-before, so the result is fully deterministic.
    static func plan(
        for requests: [SubscriptionNotificationRequest],
        now: Date = Date(),
        calendar: Calendar = .current,
        limit: Int = systemPendingLimit
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []

        for request in requests where !request.isPaused && request.renewalDate > now {
            for daysBefore in request.daysBeforeOptions {
                guard let fire = fireDate(
                    renewalDate: request.renewalDate,
                    daysBeforeRenewal: daysBefore,
                    now: now,
                    calendar: calendar
                ) else { continue }
                planned.append(PlannedNotification(
                    subscriptionID: request.subscriptionID,
                    subscriptionName: request.subscriptionName,
                    daysBeforeRenewal: daysBefore,
                    fireDate: fire
                ))
            }
        }

        let ordered = planned.sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            if lhs.subscriptionName != rhs.subscriptionName { return lhs.subscriptionName < rhs.subscriptionName }
            return lhs.daysBeforeRenewal < rhs.daysBeforeRenewal
        }
        return Array(ordered.prefix(max(0, limit)))
    }
}
