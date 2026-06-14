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

    // MARK: - Aggregation & display helpers (Part 1B §9.4 / §11.2)
    //
    // Money is kept in `Decimal` everywhere it is stored or summed. The two `Double`
    // bridges below exist only at the chart / Foundation Models boundary, where the
    // APIs (`SectorMark`, `BarMark`, `@Generable`) require `Double`. `format` stays in
    // `Decimal` end to end, so notification bodies never lose a cent to Double rounding.

    /// USD value of `amount` (given in `code`), as a `Double` for charts and the AI
    /// review snapshot. Unknown currencies pass through at face value (see `convert`).
    static func toUSD(_ amount: Decimal, code: String) -> Double {
        let usd = convert(amount, from: code, to: "USD")
        return NSDecimalNumber(decimal: usd).doubleValue
    }

    /// Inverse of `toUSD`: turn a USD `Double` back into a `Decimal` amount in `code`,
    /// for display in the user's preferred currency.
    static func fromUSD(_ usd: Double, code: String) -> Decimal {
        convert(Decimal(usd), from: "USD", to: code)
    }

    /// Localized currency string for display (notification bodies, labels). Formats
    /// `amount` in its own `currencyCode` with no conversion — `Decimal` in, `String`
    /// out, so the value shown is exact.
    static func format(_ amount: Decimal, currencyCode: String) -> String {
        amount.formatted(.currency(code: currencyCode))
    }

    // NOTE(Day 3-4): `totalMonthlyCost(subscriptions:preferredCurrency:)` from
    // Part 1A §6.4 is deferred — the Overview view model (Part 1B §11.2) sums via
    // `toUSD` / `fromUSD` inline, so no dedicated aggregate is needed yet.
}
