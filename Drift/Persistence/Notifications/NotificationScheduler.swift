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
///
/// User-set "remind me to cancel" reminders are a separate, sparse namespace
/// (`cancel-<uuid>`, one per subscription) managed by ``setCancelReminder(for:)`` and
/// ``reconcileCancelReminders(in:)``. They are independent of pause state and of the
/// renewal planner.
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

    /// One user-set cancel reminder per subscription.
    private func cancelIdentifier(subscriptionID: UUID) -> String {
        "cancel-\(subscriptionID.uuidString)"
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
        let requests = buildRequests(from: subs)

        let planned = NotificationPlanner.plan(for: requests, now: now, calendar: calendar)
        let plannedByID = Dictionary(planned.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })

        // Clear Drift's pending reminders first; only prompt for permission if there is work.
        await clearPendingRenewals()
        guard !planned.isEmpty else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        for sub in subs {
            for note in sub.unwrappedNotifications where note.isEnabled {
                let id = identifier(subscriptionID: sub.id, daysBefore: note.daysBeforeRenewal)
                guard let plan = plannedByID[id] else { continue }
                do {
                    try await center.add(notificationRequest(for: sub, note: note, fireDate: plan.fireDate))
                    note.lastScheduledFireDate = plan.fireDate
                    note.subscriptionID = sub.id   // keep the CloudKit backup link meaningful
                } catch {
                    // A failed add (e.g. a 64-cap race) is non-fatal; the next reschedule retries.
                }
            }
        }
    }

    // MARK: - Reschedule helpers

    /// Build planner inputs from the active subscriptions that have enabled reminders.
    private func buildRequests(from subs: [Subscription]) -> [SubscriptionNotificationRequest] {
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
                isPaused: sub.isPaused || sub.isCanceled,
                daysBeforeOptions: enabledDays
            ))
        }
        return requests
    }

    /// Remove every pending Drift renewal reminder (the `renewal-` namespace).
    private func clearPendingRenewals() async {
        let pending = await center.pendingNotificationRequests()
        let driftIDs = pending.map(\.identifier).filter { $0.hasPrefix("renewal-") }
        if !driftIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: driftIDs)
        }
    }

    /// Build the calendar-triggered request for one reminder. The body shows the renewal
    /// (charge) date, not the reminder's fire date.
    private func notificationRequest(
        for sub: Subscription,
        note: RenewalNotification,
        fireDate: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let dayWord = note.daysBeforeRenewal == 1 ? "day" : "days"
        content.title = "\(sub.name) renews in \(note.daysBeforeRenewal) \(dayWord)"
        let formatted = ExchangeRates.format(sub.monthlyCost, currencyCode: sub.currencyCode)
        content.body = "\(formatted) on \(sub.nextRenewalDate.formatted(date: .abbreviated, time: .omitted))."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.threadIdentifier = "renewal-\(sub.id.uuidString)"
        content.userInfo = [
            "subscriptionID": sub.id.uuidString,
            "kind": "renewal"
        ]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = identifier(subscriptionID: sub.id, daysBefore: note.daysBeforeRenewal)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    // MARK: - Cancel reminders (user-set, one per subscription)

    /// Schedule (or clear) the single "remind me to cancel" notification for one
    /// subscription. Takes only Sendable values — no SwiftData model — so the caller can
    /// read them on the main actor and hand them to a task without crossing a `@Model`
    /// across threads. A `nil` or past `fireDate` clears the reminder.
    func setCancelReminder(
        id: UUID,
        name: String,
        monthlyCost: Decimal,
        currencyCode: String,
        fireDate: Date?
    ) async {
        center.removePendingNotificationRequests(withIdentifiers: [cancelIdentifier(subscriptionID: id)])

        guard let fireDate, fireDate > Date() else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let request = cancelRequest(
            id: id, name: name, monthlyCost: monthlyCost, currencyCode: currencyCode, fireDate: fireDate
        )
        do {
            try await center.add(request)
        } catch {
            // Non-fatal; the next reconcile retries.
        }
    }

    /// Clear and re-add every cancel reminder from the stored dates. Local notifications
    /// don't survive a reinstall, but `cancelReminderDate` does (SwiftData/CloudKit), so
    /// this restores them on launch. Reads the shared main context on the main actor — no
    /// context is passed across an async boundary. Idempotent; prompts for permission only
    /// if at least one future reminder exists.
    public func reconcileCancelReminders() async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix("cancel-") }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        let context = SharedModelContainer.shared.mainContext
        let now = Date()
        let subs = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        // Snapshot only the Sendable fields we need, on the main actor, before any await.
        let due = subs.compactMap { CancelReminderInfo(subscription: $0, after: now) }
        guard !due.isEmpty else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        for item in due {
            let request = cancelRequest(
                id: item.id, name: item.name, monthlyCost: item.monthlyCost,
                currencyCode: item.currencyCode, fireDate: item.fireDate
            )
            do {
                try await center.add(request)
            } catch {
                // Non-fatal.
            }
        }
    }

    /// A plain (category-less) reminder so the only interaction is a tap, which opens the
    /// subscription's detail — where the matching cancellation guide lives. Built from
    /// Sendable values only.
    private func cancelRequest(
        id: UUID,
        name: String,
        monthlyCost: Decimal,
        currencyCode: String,
        fireDate: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Time to cancel \(name)?"
        let formatted = ExchangeRates.format(monthlyCost, currencyCode: currencyCode)
        content.body = "Tap to review it and stop paying \(formatted)/mo if you're done."
        content.sound = .default
        content.threadIdentifier = "cancel-\(id.uuidString)"
        content.userInfo = [
            "subscriptionID": id.uuidString,
            "kind": "cancel"
        ]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(
            identifier: cancelIdentifier(subscriptionID: id),
            content: content,
            trigger: trigger
        )
    }

    // MARK: - Targeted cancel (e.g. on delete or pause)

    /// Remove a subscription's pending reminders — both renewal reminders and its
    /// cancel reminder. Call on delete.
    public func cancel(subscriptionID: UUID) async {
        let renewalPrefix = "renewal-\(subscriptionID.uuidString)-"
        let cancelID = cancelIdentifier(subscriptionID: subscriptionID)
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter {
            $0.hasPrefix(renewalPrefix) || $0 == cancelID
        }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationScheduler: @MainActor UNUserNotificationCenterDelegate {
    // No `nonisolated`: under Default Actor Isolation = MainActor, an isolated
    // conformance keeps these on the main actor. Marking them `nonisolated` runs the
    // bridged async completion off-main → "Call must be made on main thread" on tap.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public func userNotificationCenter(
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
            DriftDeepLinkRouter.shared.open(subscriptionID: subscriptionID)
        case UNNotificationDismissActionIdentifier:
            break
        default:
            break
        }
    }
}

// MARK: - Cancel reminder snapshot

/// A Sendable snapshot of the fields a cancel reminder needs, so a `@Model` never has to
/// cross an async boundary. Built on the main actor while reconciling.
private struct CancelReminderInfo {
    let id: UUID
    let name: String
    let monthlyCost: Decimal
    let currencyCode: String
    let fireDate: Date

    /// Returns `nil` unless the subscription has a cancel reminder dated after `date`.
    @MainActor
    init?(subscription: Subscription, after date: Date) {
        guard let fire = subscription.cancelReminderDate, fire > date else { return nil }
        self.id = subscription.id
        self.name = subscription.name
        self.monthlyCost = subscription.monthlyCost
        self.currencyCode = subscription.currencyCode
        self.fireDate = fire
    }
}
