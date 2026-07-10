//
//  PrivacyView.swift
//  Drift
//
//  A calm, plain-language statement of what Drift never does. It mirrors the
//  App Store "what Drift does not do" section so the promise is visible inside
//  the app too — not to alarm, just to reassure. Everything stays on device.
//

import SwiftUI

struct PrivacyView: View {
    private struct Promise: Identifiable {
        let text: String
        var id: String { text }
    }

    /// The promises, as an array so items are easy to add or reword later.
    private static let promises: [Promise] = [
        Promise(text: "No bank connection"),
        Promise(text: "No access to your email or messages"),
        Promise(text: "No ads"),
        Promise(text: "No tracking across apps"),
        Promise(text: "No nagging, guilt, or scare tactics"),
        Promise(text: "No subscription — pay once")
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.promises) { promise in
                    HStack(spacing: DriftSpacing.s12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DriftTheme.accent)
                        Text(promise.text)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Your data stays yours")
            } footer: {
                Text("Everything is stored on your device. If you turn on iCloud sync, it uses your own private iCloud, which the developer cannot read. There are no analytics or third-party trackers in Drift. The App Store privacy label reads: Data Not Collected.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
