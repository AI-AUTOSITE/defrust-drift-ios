//
//  DarkPatternBadge.swift
//  Drift
//
//  A small pill showing a cancellation-friction score (1...10). Meaning is
//  carried by a number, an icon AND a label — never by color alone (WCAG 1.4.1).
//

import SwiftUI

struct DarkPatternBadge: View {
    let score: Int

    private var label: String {
        switch score {
        case ...3: return "Easy"
        case 4...6: return "Some friction"
        default: return "Major friction"
        }
    }

    private var symbol: String {
        switch score {
        case ...3: return "checkmark.shield"
        case 4...6: return "exclamationmark.circle"
        default: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        HStack(spacing: DriftSpacing.s4) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
            Text("\(score)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.subheadline)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DriftSpacing.s8)
        .padding(.vertical, DriftSpacing.s4)
        .background(Capsule().fill(DriftTheme.darkPatternColor(score: score)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cancellation difficulty \(score) out of 10. \(label).")
    }
}
