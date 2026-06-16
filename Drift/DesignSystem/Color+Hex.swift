//
//  Color+Hex.swift
//  Drift
//
//  Renders the hex color strings stored on the SwiftData models
//  (`Category.colorHex`, `Subscription.customColor`) as SwiftUI colors.
//  The brand / semantic palette lives in the asset catalog instead — see
//  `DriftTheme`. Category colors are per-instance hex on the model, so they
//  are NOT asset-catalog colors and must go through `Color(hex:)`.
//

import Foundation
import SwiftUI

/// RGB components in the 0...1 range.
///
/// A named struct rather than a tuple: SwiftLint's `large_tuple` rule caps
/// tuples at two members, and a struct gives the parser a value that is easy
/// to assert on in tests.
struct DriftRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double
}

/// Parses 6-digit hex color strings such as `"#5E5CE6"` or `"5E5CE6"`.
enum HexColor {
    /// Returns the parsed components, or `nil` when `hex` is not a valid
    /// 6-digit value. Leading `#` and surrounding spaces are ignored.
    static func rgb(from hex: String) -> DriftRGB? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return nil
        }
        return DriftRGB(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Color {
    /// Creates a color from a hex string. Falls back to `fallback` when the
    /// string cannot be parsed, so a malformed stored value can never crash
    /// the UI — it just renders a neutral color.
    init(hex: String, fallback: Color = .secondary) {
        guard let rgb = HexColor.rgb(from: hex) else {
            self = fallback
            return
        }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
