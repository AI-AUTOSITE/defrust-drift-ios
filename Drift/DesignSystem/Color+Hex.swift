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
import UIKit

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

    /// A category/subscription tint that stays legible in both appearances.
    ///
    /// The stored vivid hex reads well on dark backgrounds, so dark mode uses it
    /// unchanged. On a light (white) background several of these — yellow, green,
    /// orange, light blue — fall below the WCAG 3:1 non-text contrast bar and
    /// wash out, so light mode darkens the color (keeping its hue) just until it
    /// clears 3:1. Colors that already pass are untouched, and existing stored
    /// data needs no migration because the adjustment happens at render time.
    static func categoryTint(hex: String, fallback: Color = .secondary) -> Color {
        guard let rgb = HexColor.rgb(from: hex) else { return fallback }
        let base = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? base : base.darkenedForContrastOnWhite(3.0)
        })
    }
}

private extension UIColor {
    /// Returns the receiver unchanged if it already meets `target` contrast
    /// against white, otherwise a darker, slightly more saturated variant that
    /// does. Hue is preserved so the color stays recognizable.
    func darkenedForContrastOnWhite(_ target: CGFloat) -> UIColor {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha) else { return self }
        var result = self
        var steps = 0
        while result.contrastAgainstWhite() < target && steps < 25 {
            bri = max(0, bri - 0.04)
            sat = min(1, sat + 0.02)
            result = UIColor(hue: hue, saturation: sat, brightness: bri, alpha: alpha)
            steps += 1
        }
        return result
    }

    /// WCAG contrast ratio of the receiver against white (luminance 1.0).
    func contrastAgainstWhite() -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        return 1.05 / (luminance + 0.05)
    }
}
