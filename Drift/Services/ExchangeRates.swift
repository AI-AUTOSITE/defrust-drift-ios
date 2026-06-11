import Foundation

/// Static exchange rate table. Rates are multipliers against USD = 1.0.
/// Updated manually with every release (quarterly cadence — see Part 1A §6.5).
/// No network calls, ever: local-first by design.
struct ExchangeRates {

    /// Rate reference date: 2026-05-25 (MTFX mid-market rates).
    /// When updating, replace the timeIntervalSince1970 value with the new timestamp.
    static let asOfDate: Date = Date(timeIntervalSince1970: 1748131200) // 2026-05-25 00:00:00 UTC

    /// Amount of each currency per 1 USD.
    /// Source: MTFX mid-market rates, week of 2026-05-25 (mtfxgroup.com).
    /// Next update: refer to a mid-market source such as MTFX or OFX.
    static let rates: [String: Decimal] = [
        "USD": 1.000,
        "GBP": 0.745,
        "CAD": 1.380,
        "AUD": 1.402
    ]

    /// Convert an amount between currencies via USD.
    /// Unknown currencies are returned unchanged — the call site is responsible
    /// for showing a warning (Part 1A contract).
    static func convert(_ amount: Decimal, from: String, to: String) -> Decimal {
        guard from != to else { return amount }
        guard let fromRate = rates[from], let toRate = rates[to] else {
            return amount
        }
        // amount (from) -> amount / fromRate (USD) -> * toRate (to)
        let inUSD = amount / fromRate
        return inUSD * toRate
    }

    // NOTE(Day 3-4): `totalMonthlyCost(subscriptions:preferredCurrency:)` from
    // Part 1A §6.4 is added once the `Subscription` SwiftData model exists
    // (drift-part-1a-core-schema.md §2.4). Day 1 stays free of SwiftData.
}
