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
}
