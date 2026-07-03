import SwiftUI

/// How to cancel a subscription billed through a *platform* (Apple, Google,
/// Amazon, Roku, …) rather than directly by the service. Also reused for
/// `.directWeb` as the generic "cancel on the service's own site" screen.
///
/// Styling mirrors `CancellationGuideDetail`. (Design:
/// docs/cancellation-billing-channel-design.md)
struct BillingChannelGuideView: View {
    let channel: BillingChannel
    /// The tracked subscription's name, for a friendlier opening line.
    let serviceName: String

    var body: some View {
        List {
            Section {
                if !trimmedName.isEmpty {
                    Text("\(trimmedName) is billed through \(channel.displayName).")
                        .font(.body)
                }
                if let gotcha = channel.gotcha {
                    Label(gotcha, systemImage: "exclamationmark.bubble")
                        .font(.footnote)
                }
            }

            if let url = channel.managementURL {
                Section {
                    ExternalLinkButton(url: url) {
                        Label("Open \(channel.displayName) to cancel",
                              systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("Opens where this subscription is managed.")
                }
            }

            Section("Steps") {
                ForEach(Array(channel.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .font(.body)
                        .padding(.vertical, 2)
                }
            }

            if !relevantGotchas.isEmpty {
                Section("Good to know") {
                    ForEach(relevantGotchas, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(DriftTheme.subtleText)
                    }
                }
            }

            Section {
                Text("Steps last verified \(channel.lastVerified).")
                    .font(.caption)
                    .foregroundStyle(DriftTheme.subtleText)
            }
        }
        .navigationTitle("How to cancel")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trimmedName: String {
        serviceName.trimmingCharacters(in: .whitespaces)
    }

    /// The universal reminders that make sense for this channel. The
    /// "deleting the app" / "cancel through the platform" notes only apply to
    /// store-billed subscriptions, so for a direct/unknown channel we show just
    /// the end-of-period and free-trial reminders.
    private var relevantGotchas: [String] {
        switch channel {
        case .directWeb, .unknown:
            return Array(BillingChannel.universalGotchas.suffix(2))
        default:
            return BillingChannel.universalGotchas
        }
    }
}
