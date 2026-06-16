//
//  DriftMotion.swift
//  Drift
//
//  Animation tokens. Calm and grounded — never bouncy or springy.
//  Respect Reduce Motion at call sites (e.g. gate chart redraws).
//

import SwiftUI

enum DriftMotion {
    /// General transitions: sheets presenting, list rows updating.
    static let smooth = Animation.smooth(duration: 0.30)

    /// Quick affordances: toggles, selection, small taps.
    static let snappy = Animation.snappy(duration: 0.20)

    /// Charts drawing in on first appear.
    static let chartAppear = Animation.easeOut(duration: 0.6)
}
