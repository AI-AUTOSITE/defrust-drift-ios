//
//  PaywallView.swift
//  Drift
//
//  Drift Pro is a single one-time purchase ($14.99, Family Sharing). This screen
//  states the value plainly and lets the user buy, restore, or just leave — no
//  countdowns, no fake scarcity, no nagging (Part 2 anti-dark-pattern rule).
//
//  ⚠️ FEATURE LIST: `proFeatures` lists ONLY what actually ships in v1.0.
//  Promising unbuilt features breaks the "honest" brand promise and risks App
//  Review rejection. Add export / Live Activity / Watch / receipt parsing back
//  only once they actually ship.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(DriftStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false

    private let productID = "com.defrust.drift.pro.lifetime"

    /// v1.0 Pro features — committed to ship by launch. Add more only once
    /// they are actually built (see the warning above).
    private let proFeatures = [
        "Track unlimited subscriptions",
        "Reminders 3, 7, and 14 days ahead"
    ]

    private var proProduct: Product? {
        store.products.first { $0.id == productID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DriftSpacing.s32) {
                    header
                    if store.isPro {
                        ownedState
                    } else {
                        featureList
                        purchaseSection
                    }
                }
                .padding(.horizontal, DriftSpacing.s24)
                .padding(.vertical, DriftSpacing.s24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Drift Pro")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DriftTheme.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: store.isPro) { wasPro, nowPro in
                if !wasPro && nowPro { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: DriftSpacing.s12) {
            Image(systemName: "infinity")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(DriftTheme.accent)

            Text("One purchase. Yours for good.")
                .font(DriftTypography.sectionTitle)
                .multilineTextAlignment(.center)

            Text("No subscription, no ads, no selling your data. "
                 + "Pay once and Drift Pro is yours — shareable with your family.")
                .font(.subheadline)
                .foregroundStyle(DriftTheme.subtleText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, DriftSpacing.s8)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: DriftSpacing.s16) {
            ForEach(proFeatures, id: \.self) { feature in
                HStack(alignment: .firstTextBaseline, spacing: DriftSpacing.s12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DriftTheme.success)
                    Text(feature)
                        .font(.body)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var purchaseSection: some View {
        VStack(spacing: DriftSpacing.s12) {
            Button {
                buy()
            } label: {
                Text(buyButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DriftSpacing.s4)
            }
            .buttonStyle(.borderedProminent)
            .tint(DriftTheme.accent)
            .disabled(proProduct == nil || isPurchasing)

            Button("Restore Purchases") { restore() }
                .font(.subheadline)
                .disabled(isPurchasing)

            Text("One-time purchase. Family Sharing supported.")
                .font(DriftTypography.caption)
                .foregroundStyle(DriftTheme.subtleText)
        }
    }

    private var ownedState: some View {
        VStack(spacing: DriftSpacing.s12) {
            Label("You're on Drift Pro", systemImage: "checkmark.seal.fill")
                .font(DriftTypography.sectionTitle)
                .foregroundStyle(DriftTheme.success)

            Text("Thanks for supporting independent, honest software.")
                .font(.subheadline)
                .foregroundStyle(DriftTheme.subtleText)
                .multilineTextAlignment(.center)
        }
    }

    private var buyButtonTitle: String {
        if let price = proProduct?.displayPrice {
            return "Get Drift Pro — \(price)"
        }
        return "Get Drift Pro"
    }

    private func buy() {
        guard let product = proProduct else { return }
        isPurchasing = true
        Task { @MainActor in
            _ = try? await store.purchase(product)
            isPurchasing = false
        }
    }

    private func restore() {
        isPurchasing = true
        Task { @MainActor in
            await store.restorePurchases()
            isPurchasing = false
        }
    }
}
