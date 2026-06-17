@testable import Drift
import Foundation
import Testing

@Suite("BillingCycle")
struct BillingCycleTests {

    @Test("Months conversion",
          arguments: zip(
            [BillingCycle.weekly, .monthly, .quarterly, .yearly],
            [Decimal(1) / Decimal(4), Decimal(1), Decimal(3), Decimal(12)]
          ))
    func monthsValue(cycle: BillingCycle, expected: Decimal) {
        #expect(cycle.months == expected)
    }

    @Test("Custom cycle months is 0 (computed from customCycleDays on Subscription)")
    func customCycleContract() {
        // Part 1A §2.3 contract: `.custom` returns 0; the real length lives in
        // `Subscription.customCycleDays`. (The 1C-2 sample assumed an
        // associated-value enum — the 1A String-backed schema is canonical.)
        #expect(BillingCycle.custom.months == 0)
    }

    @Test("Raw value round-trips for schema storage",
          arguments: BillingCycle.allCases)
    func rawValueRoundTrip(cycle: BillingCycle) {
        // Subscription stores `billingCycleRaw: String`; this property is the
        // contract that storage round-trips losslessly.
        #expect(BillingCycle(rawValue: cycle.rawValue) == cycle)
    }

    // MARK: - Cost normalization

    @Test("Per-cycle price normalizes to the stored monthly cost")
    func monthlyCostFromCycle() {
        // The amount the user enters per cycle → the normalized monthly figure.
        #expect(BillingCycle.monthly.monthlyCost(forCycleAmount: Decimal(999) / Decimal(100))
                == Decimal(999) / Decimal(100)) // 9.99/mo → 9.99/mo
        #expect(BillingCycle.yearly.monthlyCost(forCycleAmount: Decimal(120)) == Decimal(10))    // 120/yr → 10/mo
        #expect(BillingCycle.quarterly.monthlyCost(forCycleAmount: Decimal(30)) == Decimal(10))  // 30/qtr → 10/mo
        #expect(BillingCycle.weekly.monthlyCost(forCycleAmount: Decimal(5)) == Decimal(20))      // 5/wk → 20/mo
    }

    @Test("Custom day-count cycle normalizes by average month length")
    func customCostFromCycle() {
        // 60-day cycle at $30 ≈ $15.21875/mo (≈1.9712 cycles per 30.4375-day month).
        let monthly = BillingCycle.custom.monthlyCost(forCycleAmount: Decimal(30), customCycleDays: 60)
        let expected = Decimal(1_521_875) / Decimal(100_000) // 15.21875
        let tolerance = Decimal(1) / Decimal(10_000)         // 0.0001
        #expect(abs(monthly - expected) < tolerance)
    }

    @Test("Monthly cost round-trips back to the per-cycle amount",
          arguments: [BillingCycle.weekly, .monthly, .quarterly, .yearly])
    func costRoundTrip(cycle: BillingCycle) {
        let perCycle = Decimal(24)
        let monthly = cycle.monthlyCost(forCycleAmount: perCycle)
        #expect(cycle.cycleAmount(forMonthlyCost: monthly) == perCycle)
    }

    // MARK: - Renewal dates

    @Test("nextDate advances by exactly one cycle")
    func nextDateAdvances() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 10)))

        let weekly    = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 17)))
        let monthly   = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let quarterly = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let yearly    = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 10)))
        let custom    = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 20)))

        #expect(BillingCycle.weekly.nextDate(after: start, calendar: calendar) == weekly)
        #expect(BillingCycle.monthly.nextDate(after: start, calendar: calendar) == monthly)
        #expect(BillingCycle.quarterly.nextDate(after: start, calendar: calendar) == quarterly)
        #expect(BillingCycle.yearly.nextDate(after: start, calendar: calendar) == yearly)
        #expect(BillingCycle.custom.nextDate(after: start, customCycleDays: 10, calendar: calendar) == custom)
    }

    @Test("nextRenewal rolls a past anchor forward to the next future occurrence")
    func nextRenewalRollsForward() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt

        let seed      = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 10)))
        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 20)))
        let expected  = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))

        let rolled = BillingCycle.monthly.nextRenewal(onOrAfter: reference, seed: seed, calendar: calendar)
        #expect(rolled == expected)

        // A seed already on/after the reference is returned unchanged.
        let futureSeed = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        let unchanged = BillingCycle.monthly.nextRenewal(onOrAfter: reference, seed: futureSeed, calendar: calendar)
        #expect(unchanged == futureSeed)
    }
}
