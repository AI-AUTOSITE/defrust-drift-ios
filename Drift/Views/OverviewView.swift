//
//  OverviewView.swift
//  Drift
//
//  At-a-glance monthly total. Charts, "vs. last month", upcoming renewals and
//  the cumulative-savings card arrive with the fuller Overview build-out; this
//  step is the hero number (now multi-currency) plus an empty state.
//

import SwiftData
import SwiftUI

struct OverviewView: View {
    @Query(sort: \Subscription.nextRenewalDate)
    private var subscriptions: [Subscription]

    /// Paused subscriptions are excluded. Filtered in memory to sidestep
    /// SwiftData predicate quirks (and the set is tiny).
    private var activeSubscriptions: [Subscription] {
        subscriptions.filter { !$0.isPaused }
    }

    /// Sum of every active subscription, each converted from its own currency
    /// into USD first so mixed-currency totals are correct (Part 1B §11.2).
    private var monthlyTotalUSD: Decimal {
        activeSubscriptions.reduce(Decimal.zero) { partial, subscription in
            partial + ExchangeRates.convert(
                subscription.monthlyCost,
                from: subscription.currencyCode,
                to: "USD"
            )
        }
    }

    private var yearlyTotalUSD: Decimal {
        monthlyTotalUSD * 12
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

                Text("\(yearlyTotalUSD.formatted(.currency(code: "USD"))) / year")
                    .font(DriftTypography.caption)
                    .foregroundStyle(DriftTheme.subtleText)

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
