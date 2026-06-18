//
//  SettingsView.swift
//  Drift
//
//  Reached from the gearshape on the Overview screen. Drift keeps three tabs;
//  Settings is a sheet, not a fourth tab. This first pass covers the display
//  currency and the Pro section. Per the anti-dark-pattern rule (Part 2 §10),
//  Restore and Request a Refund both live here, two taps in — never hidden.
//
//  Notifications and iCloud sync get their own sections later: iCloud once the
//  App Group / CloudKit capability is configured, notifications once lead-time
//  preferences (and their Pro gating) are designed.
//

import SwiftUI

struct SettingsView: View {
    @Environment(DriftStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Currency the Overview total is shown in. Device-local (UserDefaults), so
    /// nothing leaves the device. Defaults to USD to match prior behavior.
    @AppStorage("preferredCurrencyCode") private var preferredCurrencyCode = "USD"

    /// Disables the Pro actions while a StoreKit call is in flight.
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                proSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DriftTheme.accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            Picker("Preferred currency", selection: $preferredCurrencyCode) {
                ForEach(ExchangeRates.rates.keys.sorted(), id: \.self) { code in
                    Text(code).tag(code)
                }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Your monthly total is shown in this currency. "
                 + "Each subscription still shows the amount you're actually billed.")
        }
    }

    // MARK: - Drift Pro

    private var proSection: some View {
        Section("Drift Pro") {
            LabeledContent("Status") {
                if store.isPro {
                    Label("Active", systemImage: "checkmark.seal.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(DriftTheme.success)
                } else {
                    Text("Free")
                        .foregroundStyle(DriftTheme.subtleText)
                }
            }

            Button("Restore Purchases") { restore() }
                .disabled(isWorking)

            if store.isPro {
                Button("Request a Refund") { refund() }
                    .disabled(isWorking)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text(appVersion)
                    .foregroundStyle(DriftTheme.subtleText)
            }
        } header: {
            Text("About")
        } footer: {
            Text("defrust — calm software, paid once.")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

    private func restore() {
        isWorking = true
        Task { @MainActor in
            await store.restorePurchases()
            isWorking = false
        }
    }

    private func refund() {
        isWorking = true
        Task { @MainActor in
            await store.requestRefund()
            isWorking = false
        }
    }
}
