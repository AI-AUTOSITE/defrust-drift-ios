import SwiftUI

/// A button that opens an external URL (the App Store, Safari, …) but first
/// asks for confirmation, so the user is never pulled out of Drift unexpectedly.
/// The confirmation offers an "open and don't ask again" choice; once chosen,
/// the global `skipExternalLinkConfirmation` flag skips the prompt everywhere.
///
/// Reuse this for ANY out-of-app link — cancellation pages, the App Store
/// subscriptions screen, and future Privacy Policy / Terms links — so they all
/// get the same guard for free.
///
/// The flag is a single UI setting in `UserDefaults` (no personal data, no
/// tracking); it deliberately does not sync via CloudKit (a per-device choice).
struct ExternalLinkButton<Label: View>: View {
    let url: URL
    @ViewBuilder var label: () -> Label

    @AppStorage("skipExternalLinkConfirmation") private var skipConfirmation = false
    @Environment(\.openURL) private var openURL
    @State private var isConfirming = false

    var body: some View {
        Button {
            if skipConfirmation {
                openURL(url)
            } else {
                isConfirming = true
            }
        } label: {
            label()
        }
        .alert("Leave Drift?", isPresented: $isConfirming) {
            Button("Open") { openURL(url) }
            Button("Open and Don't Ask Again") {
                skipConfirmation = true
                openURL(url)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This opens outside Drift, in the App Store or your browser.")
        }
    }
}
