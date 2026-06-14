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
    /// `.custom` returns 0 — the actual length is computed from
    /// `Subscription.customCycleDays` instead.
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
