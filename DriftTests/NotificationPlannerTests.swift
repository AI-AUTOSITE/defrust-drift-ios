import Foundation
import Testing
@testable import Drift

@Suite("NotificationPlanner — fire dates & 64-cap")
struct NotificationPlannerTests {

    private let cal = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_750_000_000)  // fixed reference point

    private func request(
        name: String = "Service",
        renewalInDays: Int,
        paused: Bool = false,
        daysBefore: [Int] = [1, 3, 7]
    ) -> SubscriptionNotificationRequest {
        let renewal = cal.date(byAdding: .day, value: renewalInDays, to: now) ?? now
        return SubscriptionNotificationRequest(
            subscriptionID: UUID(),
            subscriptionName: name,
            renewalDate: renewal,
            isPaused: paused,
            daysBeforeOptions: daysBefore
        )
    }

    @Test("Fire date is N days before renewal, in the future")
    func fireDateInFuture() {
        let renewal = cal.date(byAdding: .day, value: 10, to: now) ?? now
        let fire = NotificationPlanner.fireDate(renewalDate: renewal, daysBeforeRenewal: 3, now: now, calendar: cal)
        #expect(fire == cal.date(byAdding: .day, value: 7, to: now))
    }

    @Test("A reminder whose fire date is already past is dropped")
    func pastReminderDropped() {
        let renewal = cal.date(byAdding: .day, value: 2, to: now) ?? now
        // 7 days before a renewal only 2 days away → 5 days ago → past.
        let fire = NotificationPlanner.fireDate(renewalDate: renewal, daysBeforeRenewal: 7, now: now, calendar: cal)
        #expect(fire == nil)
    }

    @Test("Paused subscriptions produce no notifications")
    func pausedProducesNothing() {
        let plan = NotificationPlanner.plan(for: [request(renewalInDays: 30, paused: true)], now: now, calendar: cal)
        #expect(plan.isEmpty)
    }

    @Test("Past renewals produce no notifications")
    func pastRenewalProducesNothing() {
        let plan = NotificationPlanner.plan(for: [request(renewalInDays: -5)], now: now, calendar: cal)
        #expect(plan.isEmpty)
    }

    @Test("Only still-future reminders within a request are kept")
    func mixedDaysBeforeFiltered() {
        // Renewal in 2 days: only the 1-day-before reminder is still in the future.
        let plan = NotificationPlanner.plan(for: [request(renewalInDays: 2, daysBefore: [1, 3, 7])], now: now, calendar: cal)
        #expect(plan.count == 1)
        #expect(plan.first?.daysBeforeRenewal == 1)
    }

    @Test("Result is capped at the limit, keeping the soonest, in ascending order")
    func capsAtLimit() {
        // 30 subscriptions × 3 reminders = 90 future candidates.
        let requests = (1...30).map { request(name: "S\($0)", renewalInDays: 40 + $0) }
        let plan = NotificationPlanner.plan(for: requests, now: now, calendar: cal, limit: 64)
        #expect(plan.count == 64)

        let dates = plan.map(\.fireDate)
        #expect(dates == dates.sorted())

        let allFireDates = requests.flatMap { req in
            req.daysBeforeOptions.compactMap {
                NotificationPlanner.fireDate(renewalDate: req.renewalDate, daysBeforeRenewal: $0, now: now, calendar: cal)
            }
        }
        #expect(plan.first?.fireDate == allFireDates.min())
    }

    @Test("Identifier matches the renewal-<uuid>-<days> scheme")
    func identifierScheme() throws {
        let req = request(renewalInDays: 10, daysBefore: [3])
        let plan = NotificationPlanner.plan(for: [req], now: now, calendar: cal)
        let planned = try #require(plan.first)
        #expect(planned.id == "renewal-\(req.subscriptionID.uuidString)-3")
    }

    @Test("Empty input yields an empty plan")
    func emptyInput() {
        #expect(NotificationPlanner.plan(for: [], now: now, calendar: cal).isEmpty)
    }

    @Test("A limit of zero yields nothing (and does not crash)")
    func zeroLimit() {
        let plan = NotificationPlanner.plan(for: [request(renewalInDays: 30)], now: now, calendar: cal, limit: 0)
        #expect(plan.isEmpty)
    }
}
