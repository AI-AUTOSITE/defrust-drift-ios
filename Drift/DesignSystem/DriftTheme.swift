//
//  DriftTheme.swift
//  Drift
//
//  Brand and semantic colors, backed by named color sets in the app's
//  asset catalog (each has a Light and Dark appearance). Import these
//  instead of hard-coding colors so light/dark and future tweaks stay
//  in one place.
//
//  NOTE: category colors are intentionally NOT here. Categories are a
//  SwiftData model (`DriftSchemaV1.Category`) and carry their own
//  `colorHex`, so they render through `Color(hex:)` (see Color+Hex.swift).
//

import SwiftUI

enum DriftTheme {

    // MARK: - Brand accent (calm teal — "drift / water")

    /// Primary accent. Light `#2AA9B5` / Dark `#3FC7D4`.
    static let accent = Color("DriftAccent")
    /// Deeper accent for pressed states and text on tint. `#1E7780`.
    static let accentDeep = Color("DriftAccentDeep")
    /// Muted accent for secondary fills. `#5FBDC6`.
    static let accentMuted = Color("DriftAccentMuted")
    /// Very light tinted background. Light `#E6F4F6` / Dark `#0D2A2D`.
    static let accentTinted = Color("DriftAccentTinted")

    // MARK: - Semantic

    /// Positive / savings. Light `#15803D` / Dark `#30D158`.
    static let success = Color("DriftSuccess")
    /// Soft caution (never an alarmist red). Light `#A16207` / Dark `#FFD60A`.
    static let warningSoft = Color("DriftWarningSoft")
    /// Calm "brick" red for the highest-friction cases. Light `#C44A3F` / Dark `#FF6961`.
    static let cautionCalm = Color("DriftCautionCalm")
    /// Secondary text. Light `#6B7280` / Dark `#AEAEB2`.
    static let subtleText = Color("DriftSubtleText")
    /// Neutral surface fill. Light `#F2F2F7` / Dark `#1C1C1E`.
    static let neutralFill = Color("DriftNeutralFill")
    /// Hairline strokes / dividers. Light `#D1D1D6` / Dark `#3A3A3C`.
    static let neutralStroke = Color("DriftNeutralStroke")

    // MARK: - Helpers

    /// Color for a cancellation dark-pattern score (1...10):
    /// 1–3 calm green, 4–6 soft amber, 7–10 calm red. Always pair with a
    /// number and a label so meaning never relies on color alone (WCAG 1.4.1).
    static func darkPatternColor(score: Int) -> Color {
        switch score {
        case ...3: return success
        case 4...6: return warningSoft
        default: return cautionCalm
        }
    }
}
