import Foundation

/// Billing cycle for a subscription.
///
/// Stored as a raw `String` (see `Subscription.billingCycleRaw`) so that adding
/// new cases later never requires a SwiftData migration — lightweight migration
/// treats enum case additions on a String-backed property as safe.
/// (Spec: drift-part-1a-core-schema.md §2.3)
enum BillingCycle: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case quarterly
    case yearly
    case custom

    var id: String { rawValue }

    /// Number of months, as `Decimal` to avoid floating-point drift in currency math.
    /// `.custom` returns 0 — its real length comes from `Subscription.customCycleDays`
    /// (use `monthsForCost(customCycleDays:)` for cost math instead).
    /// Weekly uses the 4-weeks-per-month convention (0.25 → ×4). See bug #22.
    var months: Decimal {
        switch self {
        case .weekly:    return Decimal(1) / Decimal(4) // ≈ 0.25
        case .monthly:   return 1
        case .quarterly: return 3
        case .yearly:    return 12
        case .custom:    return 0
        }
    }

    var displayName: String {
        switch self {
        case .weekly:    return "Weekly"
        case .monthly:   return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly:    return "Yearly"
        case .custom:    return "Custom"
        }
    }
}

// MARK: - Cost normalization
//
// `Subscription.monthlyCost` is stored as a monthly figure so totals are a plain
// sum. The form normalizes the per-cycle price the user enters into that monthly
// figure, and the editor reverses it. Both directions live here so there is a
// single source of truth (and they are pure functions, easy to test).

extension BillingCycle {
    /// Average days per calendar month (365.25 / 12), used to normalize a
    /// `.custom` cycle expressed in days into a monthly figure.
    private static let averageDaysPerMonth = Decimal(304_375) / Decimal(10_000) // 30.4375

    /// Months this cycle spans for cost purposes. Unlike `months`, this resolves
    /// `.custom` via `customCycleDays` (minimum 1 day; defaults to 30 when unset).
    func monthsForCost(customCycleDays: Int?) -> Decimal {
        switch self {
        case .custom:
            let days = Decimal(max(customCycleDays ?? 30, 1))
            return days / Self.averageDaysPerMonth
        default:
            return months
        }
    }

    /// Converts the per-cycle price the user enters into the normalized monthly
    /// cost stored on `Subscription.monthlyCost`. (Yearly /12, quarterly /3,
    /// weekly ×4, custom by days.)
    func monthlyCost(forCycleAmount amount: Decimal, customCycleDays: Int? = nil) -> Decimal {
        let span = monthsForCost(customCycleDays: customCycleDays)
        guard span > 0 else { return amount }
        return amount / span
    }

    /// Inverse of `monthlyCost(forCycleAmount:)`: the per-cycle price to show when
    /// a stored monthly cost is edited back in its own cycle.
    func cycleAmount(forMonthlyCost monthly: Decimal, customCycleDays: Int? = nil) -> Decimal {
        monthly * monthsForCost(customCycleDays: customCycleDays)
    }
}

// MARK: - Renewal dates
//
// Nothing computed `nextRenewalDate` before — new subscriptions defaulted to
// "today". These helpers derive the first upcoming renewal from the start date
// and roll a (possibly past) anchor forward to the next future occurrence.

extension BillingCycle {
    /// The calendar step for one cycle. `.custom` uses `customCycleDays`
    /// (minimum 1 day; defaults to 30 when unset).
    func dateStep(customCycleDays: Int?) -> DateComponents {
        switch self {
        case .weekly:    return DateComponents(day: 7)
        case .monthly:   return DateComponents(month: 1)
        case .quarterly: return DateComponents(month: 3)
        case .yearly:    return DateComponents(year: 1)
        case .custom:    return DateComponents(day: max(customCycleDays ?? 30, 1))
        }
    }

    /// The date exactly one cycle after `date`.
    func nextDate(after date: Date,
                  customCycleDays: Int? = nil,
                  calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: dateStep(customCycleDays: customCycleDays), to: date) ?? date
    }

    /// Rolls `seed` forward one cycle at a time until it is on or after `reference`.
    /// Used to derive the next upcoming renewal from a (possibly past) anchor.
    /// The 10k guard prevents a pathological loop on bad data.
    func nextRenewal(onOrAfter reference: Date,
                     seed: Date,
                     customCycleDays: Int? = nil,
                     calendar: Calendar = .current) -> Date {
        var result = seed
        var steps = 0
        while result < reference, steps < 10_000 {
            result = nextDate(after: result,
                              customCycleDays: customCycleDays,
                              calendar: calendar)
            steps += 1
        }
        return result
    }
}
