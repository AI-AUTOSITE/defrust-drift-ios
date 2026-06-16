//
//  OverviewView.swift
//  Drift
//
//  At-a-glance monthly total. Charts, "vs. last month", upcoming renewals and
//  the cumulative-savings card arrive with the fuller Overview build-out; this
//  step is the hero number plus an empty state.
//

import SwiftData
import SwiftUI

private typealias Subscription = DriftSchemaV1.Subscription

struct OverviewView: View {
    @Query(sort: \Subscription.nextRenewalDate)
    private var subscriptions: [Subscription]

    /// Paused subscriptions are excluded. Filtered in memory to sidestep
    /// SwiftData predicate quirks (and the set is tiny).
    private var activeSubscriptions: [Subscription] {
        subscriptions.filter { !$0.isPaused }
    }

    /// NOTE: sums raw `monthlyCost` as USD for now. Multi-currency
    /// normalization via `ExchangeRates.toUSD` lands with the full screen.
    private var monthlyTotalUSD: Decimal {
        activeSubscriptions.reduce(Decimal.zero) { $0 + $1.monthlyCost }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeSubscriptions.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions yet",
                        systemImage: "tray",
                        description: Text("Add subscriptions to see your monthly total here.")
                    )
                } else {
                    total
                }
            }
            .navigationTitle("Overview")
        }
    }

    private var total: some View {
        ScrollView {
            VStack(spacing: DriftSpacing.s8) {
                Text("This month")
                    .font(.subheadline)
                    .foregroundStyle(DriftTheme.subtleText)

                Text(monthlyTotalUSD, format: .currency(code: "USD"))
                    .font(DriftTypography.hero)
                    .minimumScaleFactor(0.6)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                Text("\(activeSubscriptions.count) active")
                    .font(DriftTypography.caption)
                    .foregroundStyle(DriftTheme.subtleText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DriftSpacing.s24)
            .padding(.horizontal, DriftSpacing.s16)
        }
    }
}
