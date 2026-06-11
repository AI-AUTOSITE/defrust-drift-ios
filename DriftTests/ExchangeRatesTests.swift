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
}
