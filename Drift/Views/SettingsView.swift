//
//  SettingsView.swift
//  Drift
//
//  Reached from the gearshape on the Overview screen. Drift keeps three tabs;
//  Settings is a sheet, not a fourth tab. Covers the display currency and the
//  Pro section. Per the anti-dark-pattern rule (Part 2 §10), Upgrade, Restore
//  and Request a Refund all live here, two taps in — never hidden.
//
//  A Developer section (DEBUG builds only — never shipped) seeds or clears
//  sample subscriptions for testing the paywall and the free-tier limit, and
//  can seed one of every model so CloudKit mirrors every record type into the
//  Development schema before it is deployed to Production.
//
//  Notifications and iCloud sync get their own sections later: iCloud once the
//  App Group / CloudKit capability is configured, notifications once lead-time
//  preferences (and their Pro gating) are designed.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(DriftStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Currency the Overview total is shown in. Device-local (UserDefaults), so
    /// nothing leaves the device. Defaults to USD to match prior behavior.
    @AppStorage("preferredCurrencyCode") private var preferredCurrencyCode = "USD"

    /// Disables the Pro actions while a StoreKit call is in flight.
    @State private var isWorking = false
    @State private var isShowingPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                categoriesSection
                proSection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DriftTheme.accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
                    .presentationDragIndicator(.visible)
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

    private var categoriesSection: some View {
        Section {
            NavigationLink {
                CategoryManagerView()
            } label: {
                Label("Manage categories", systemImage: "square.grid.2x2")
            }
        }
    }

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

            if !store.isPro {
                Button("Upgrade to Drift Pro") { isShowingPaywall = true }
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

    // MARK: - Developer (DEBUG only)

    #if DEBUG
    private struct SampleSubscription {
        let name: String
        let amount: Decimal
        let currency: String
        let cycle: BillingCycle
        let icon: String
        let color: String
    }

    private static let sampleData: [SampleSubscription] = [
        SampleSubscription(name: "Netflix", amount: 15.49, currency: "USD",
                           cycle: .monthly, icon: "play.rectangle.fill", color: "#E50914"),
        SampleSubscription(name: "ChatGPT Plus", amount: 20.00, currency: "USD",
                           cycle: .monthly, icon: "bubble.left.and.bubble.right.fill", color: "#10A37F"),
        SampleSubscription(name: "Disney+", amount: 8.99, currency: "GBP",
                           cycle: .monthly, icon: "play.tv.fill", color: "#113CCF"),
        SampleSubscription(name: "Spotify", amount: 11.99, currency: "USD",
                           cycle: .monthly, icon: "music.note", color: "#1DB954"),
        SampleSubscription(name: "iCloud+", amount: 2.99, currency: "USD",
                           cycle: .monthly, icon: "icloud.fill", color: "#3693F3"),
        SampleSubscription(name: "Crave", amount: 9.99, currency: "CAD",
                           cycle: .monthly, icon: "tv.fill", color: "#0046BE"),
        SampleSubscription(name: "Stan", amount: 12.00, currency: "AUD",
                           cycle: .monthly, icon: "play.circle.fill", color: "#0098FF"),
        SampleSubscription(name: "Amazon Prime", amount: 139.00, currency: "USD",
                           cycle: .yearly, icon: "cart.fill", color: "#FF9900"),
        SampleSubscription(name: "Adobe Creative Cloud", amount: 59.99, currency: "USD",
                           cycle: .monthly, icon: "paintbrush.fill", color: "#FF0000"),
        SampleSubscription(name: "Audible", amount: 14.95, currency: "USD",
                           cycle: .monthly, icon: "headphones", color: "#F8991C")
    ]

    private var developerSection: some View {
        Section {
            Button("Add 10 sample subscriptions") { addSampleData() }
            Button("Seed sync schema (usage + reminder)") { seedSyncSchema() }
            Button("Delete all subscriptions", role: .destructive) { deleteAllData() }
        } header: {
            Text("Developer")
        } footer: {
            Text("Debug builds only — never shipped. Populate or reset sample data, "
                 + "or seed one usage record and one reminder so CloudKit creates "
                 + "every record type before deploying the schema to Production.")
        }
    }

    private func addSampleData() {
        let now = Date()
        for (index, sample) in Self.sampleData.enumerated() {
            let start = Calendar.current.date(byAdding: .day, value: -(index * 2 + 5), to: now) ?? now
            let renewal = sample.cycle.nextRenewal(onOrAfter: now, seed: start)
            let subscription = Subscription(
                name: sample.name,
                monthlyCost: sample.cycle.monthlyCost(forCycleAmount: sample.amount),
                currencyCode: sample.currency,
                billingCycle: sample.cycle,
                startDate: start,
                nextRenewalDate: renewal,
                iconName: sample.icon,
                customColor: sample.color
            )
            context.insert(subscription)
        }
        try? context.save()
    }

    /// Inserts one `UsageRecord` and one `RenewalNotification` so SwiftData
    /// mirrors `CD_UsageRecord` and `CD_RenewalNotification` into the CloudKit
    /// Development schema. Without a saved record of each type those record
    /// types never appear, and a Production schema deployed without them would
    /// reject those records once usage logging / reminders ship. Links to the
    /// first subscription when one exists (both relationships are optional).
    private func seedSyncSchema() {
        let firstSubscription = (try? context.fetch(FetchDescriptor<Subscription>()))?.first
        let usage = UsageRecord(
            subscription: firstSubscription,
            date: Date(),
            wasUsed: true,
            note: "schema seed"
        )
        let reminder = RenewalNotification(
            subscription: firstSubscription,
            daysBeforeRenewal: 3,
            isEnabled: true
        )
        context.insert(usage)
        context.insert(reminder)
        try? context.save()
    }

    private func deleteAllData() {
        let all = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        for subscription in all {
            context.delete(subscription)
        }
        try? context.save()
    }
    #endif
}
