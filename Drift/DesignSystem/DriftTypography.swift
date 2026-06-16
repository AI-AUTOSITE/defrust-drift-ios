//
//  DriftTypography.swift
//  Drift
//
//  Curated font tokens. Standard text styles (`.body`, `.headline`,
//  `.footnote`, …) are used directly at call sites; this enum only holds
//  the non-standard ones (rounded titles, monospaced-digit numerics).
//  Everything scales with Dynamic Type.
//

import SwiftUI

enum DriftTypography {
    /// Hero monthly-total number. Fixed 56pt rounded with tabular figures.
    /// Cap Dynamic Type at the view level (`.dynamicTypeSize(...accessibility2)`)
    /// and add `.minimumScaleFactor(0.6)` where it is shown.
    static let hero = Font.system(size: 56, weight: .semibold, design: .rounded)
        .monospacedDigit()

    /// Large screen titles (rounded).
    static let display = Font.system(.largeTitle, design: .rounded).weight(.semibold)

    /// Section headers (rounded).
    static let sectionTitle = Font.system(.title3, design: .rounded).weight(.semibold)

    /// Currency amounts — tabular figures so totals don't jitter as they change.
    static let amount = Font.body.monospacedDigit()

    /// Small monospaced-digit captions (dates, counts).
    static let caption = Font.caption.monospacedDigit()
}
