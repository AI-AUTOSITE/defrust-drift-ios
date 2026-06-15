import Foundation
import SwiftData
import UserNotifications

/// Schedules local renewal reminders. Local notifications only — no APNs, no server —
/// matching Drift's privacy stance.
///
/// The "which reminders, and how many" decision (including the iOS 64-pending cap)
/// lives in the pure, unit-tested ``NotificationPlanner``. This `@MainActor` type is the
/// thin system layer that asks for permission, registers the action category, and
/// reconciles `UNUserNotificationCenter` with the plan.
///
/// Because the 64 cap is global, there is one canonical operation —
/// ``rescheduleAllIfNeeded(in:)`` — meant to run after any add / edit / delete / pause and
/// from the `BGAppRefreshTask`. It is idempotent: it clears Drift's pending reminders and
/// re-adds exactly the prioritized set.
@MainActor
public final class NotificationScheduler: NSObject {
    public static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let categoryIdentifier = "drift.renewal"

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    // MARK: - Identifiers

    /// Matches ``PlannedNotification/id`` so the planner's output maps 1:1 to requests.
    private func identifier(subscriptionID: UUID, daysBefore: Int) -> String {
        "renewal-\(subscriptionID.uuidString)-\(daysBefore)"
    }

    // MARK: - Authorization (requested lazily, on the first reminder)

    @discardableResult
    public func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Action category

    private func registerCategories() {
        let markUsed = UNNotificationAction(
            identifier: "drift.action.markUsed",
            title: "Mark as used",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: "drift.action.snooze",
            title: "Snooze 1 day",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [markUsed, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Canonical reschedule

    /// Plan across all active subscriptions and reconcile pending notifications. Safe to
    /// call on every change and on background refresh — idempotent, and respects the 64
    /// cap via ``NotificationPlanner``.
    public func rescheduleAllIfNeeded(in context: ModelContext) async {
        let now = Date()
        let calendar = Calendar.current

        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate<Subscription> { !$0.isPaused },
            sortBy: [SortDescriptor(\.nextRenewalDate, order: .forward)]
        )
        let subs = (try? context.fetch(descriptor)) ?? []

        var requests: [SubscriptionNotificationRequest] = []
        for sub in subs {
            let enabledDays = sub.unwrappedNotifications
                .filter { $0.isEnabled }
                .map { $0.daysBeforeRenewal }
            guard !enabledDays.isEmpty else { continue }
            requests.append(SubscriptionNotificationRequest(
                subscriptionID: sub.id,
                subscriptionName: sub.name,
                renewalDate: sub.nextRenewalDate,    // non-optional Date — used directly (bug #12)
                isPaused: sub.isPaused,
                daysBeforeOptions: enabledDays
            ))
        }

        let planned = NotificationPlanner.plan(for: requests, now: now, calendar: calendar)
        let plannedByID = Dictionary(planned.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })

        // Clear Drift's pending reminders first; only prompt for permission if there is work.
        let pending = await center.pendingNotificationRequests()
        let driftIDs = pending.map(\.identifier).filter { $0.hasPrefix("renewal-") }
        if !driftIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: driftIDs)
        }
        guard !planned.isEmpty else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        for sub in subs {
            for note in sub.unwrappedNotifications where note.isEnabled {
                let id = identifier(subscriptionID: sub.id, daysBefore: note.daysBeforeRenewal)
                guard let plan = plannedByID[id] else { continue }

                let content = UNMutableNotificationContent()
                let dayWord = note.daysBeforeRenewal == 1 ? "day" : "days"
                content.title = "\(sub.name) renews in \(note.daysBeforeRenewal) \(dayWord)"
                let formatted = ExchangeRates.format(sub.monthlyCost, currencyCode: sub.currencyCode)
                // Body shows the renewal (charge) date, not the reminder's fire date.
                content.body = "\(formatted) on \(sub.nextRenewalDate.formatted(date: .abbreviated, time: .omitted))."
                content.sound = .default
                content.categoryIdentifier = categoryIdentifier
                content.threadIdentifier = "renewal-\(sub.id.uuidString)"
                content.userInfo = [
                    "subscriptionID": sub.id.uuidString,
                    "kind": "renewal"
                ]

                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                do {
                    try await center.add(request)
                    note.lastScheduledFireDate = plan.fireDate
                    note.subscriptionID = sub.id   // keep the CloudKit backup link meaningful
                } catch {
                    // A failed add (e.g. a 64-cap race) is non-fatal; the next reschedule retries.
                }
            }
        }
    }

    // MARK: - Targeted cancel (e.g. on delete or pause)

    public func cancel(subscriptionID: UUID) async {
        let prefix = "renewal-\(subscriptionID.uuidString)-"
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationScheduler: UNUserNotificationCenterDelegate {
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let idString = userInfo["subscriptionID"] as? String,
              let subscriptionID = UUID(uuidString: idString) else { return }

        switch response.actionIdentifier {
        case "drift.action.markUsed":
            await NotificationActionHandler.shared.recordUsage(subscriptionID: subscriptionID)
        case "drift.action.snooze":
            await NotificationActionHandler.shared.snooze(subscriptionID: subscriptionID, by: 1)
        case UNNotificationDefaultActionIdentifier:
            await DriftDeepLinkRouter.shared.open(subscriptionID: subscriptionID)
        case UNNotificationDismissActionIdentifier:
            break
        default:
            break
        }
    }
}
