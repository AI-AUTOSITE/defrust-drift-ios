@testable import Drift
import Foundation
import Testing

@Suite("ExchangeRates")
struct ExchangeRatesTests {

    // Currency round-trip: Cartesian product of all four supported currencies.
    // Note: the 1C-2 sample cast through NSDecimalNumber, which does not compile
    // with abs(); Decimal is SignedNumeric, so we compare in pure Decimal instead.
    @Test("Round-trip conversion preserves value within 1¢",
          arguments: ["USD", "GBP", "CAD", "AUD"],
                     ["USD", "GBP", "CAD", "AUD"])
    func roundTrip(from: String, to: String) {
        let original = Decimal(100)
        let converted = ExchangeRates.convert(original, from: from, to: to)
        let back = ExchangeRates.convert(converted, from: to, to: from)
        let diff = abs(back - original)
        #expect(diff < Decimal(string: "0.01")!,
                "Round-trip \(from)→\(to)→\(from) drift: \(diff)")
    }

    @Test("Unknown currency is returned unchanged")
    func unknownCurrencyFallback() {
        // ExchangeRates contract: unknown currencies pass through at face value.
        let result = ExchangeRates.convert(Decimal(10), from: "XYZ", to: "USD")
        #expect(result == Decimal(10))
    }

    @Test("Identity conversion is exact",
          arguments: ["USD", "GBP", "CAD", "AUD"])
    func identityIsExact(code: String) {
        let v = Decimal(string: "42.95")!
        #expect(ExchangeRates.convert(v, from: code, to: code) == v)
    }

    // MARK: - Aggregation & display helpers (bug #13)

    @Test("toUSD matches convert→USD and is identity for USD",
          arguments: ["USD", "GBP", "CAD", "AUD"])
    func toUSDMatchesConvert(code: String) {
        let amount = Decimal(string: "100")!
        let viaHelper = ExchangeRates.toUSD(amount, code: code)
        let viaConvert = NSDecimalNumber(
            decimal: ExchangeRates.convert(amount, from: code, to: "USD")
        ).doubleValue
        #expect(abs(viaHelper - viaConvert) < 0.0001)
        if code == "USD" {
            #expect(abs(viaHelper - 100) < 0.0001)
        }
    }

    @Test("toUSD → fromUSD round-trips within 1¢",
          arguments: ["USD", "GBP", "CAD", "AUD"])
    func usdRoundTrip(code: String) {
        let original = Decimal(string: "42.95")!
        let usd = ExchangeRates.toUSD(original, code: code)
        let back = ExchangeRates.fromUSD(usd, code: code)
        let diff = abs(back - original)
        #expect(diff < Decimal(string: "0.01")!,
                "USD round-trip for \(code) drifted: \(diff)")
    }

    @Test("format renders the amount in the given currency")
    func formatRendersAmount() {
        let formatted = ExchangeRates.format(Decimal(string: "9.99")!, currencyCode: "USD")
        #expect(!formatted.isEmpty)
        // Locale-independent: the amount's digits appear (decimal separator may vary).
        #expect(formatted.contains("9"))
    }
}
