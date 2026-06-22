//
//  DriftHaptics.swift
//  Drift
//
//  Semantic haptics mapped to SwiftUI `SensoryFeedback` (iOS 17+).
//  Attach with `.driftHaptic(_:trigger:)`; the feedback plays whenever the
//  trigger value changes.
//
//  Example:
//      .driftHaptic(.subscriptionAdded, trigger: subscriptions.count)
//

import SwiftUI

enum DriftHaptic {
    case subscriptionAdded
    case subscriptionDeleted
    case subscriptionPaused
    case proPurchased
    case renewalSoon
    case navigationLight

    var feedback: SensoryFeedback {
        switch self {
        case .subscriptionAdded, .proPurchased:
            return .success
        case .subscriptionDeleted:
            return .impact(weight: .light, intensity: 0.6)
        case .subscriptionPaused:
            // A calm, neutral tick for a reversible state toggle (pause/resume).
            return .selection
        case .renewalSoon:
            return .warning
        case .navigationLight:
            return .selection
        }
    }
}

extension View {
    /// Plays the given Drift haptic each time `trigger` changes.
    func driftHaptic<T: Equatable>(_ haptic: DriftHaptic, trigger: T) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }
}
