//
//  OverviewView.swift
//  Drift
//
//  At-a-glance monthly state. Builds out in steps: the multi-currency hero
//  total plus, now, an "Upcoming renewals" rail showing what renews in the
//  next 30 days. Charts, "vs. last month" and the Pro savings card come later.
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

    /// Active subscriptions renewing within the next 30 days, soonest first.
    private var upcomingRenewals: [Subscription] {
        let now = Date()
        guard let limit = Calendar.current.date(byAdding: .day, value: 30, to: now) else {
            return []
        }
        return activeSubscriptions
            .filter { $0.nextRenewalDate >= now && $0.nextRenewalDate <= limit }
            .sorted { $0.nextRenewalDate < $1.nextRenewalDate }
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
                    content
                }
            }
            .navigationTitle("Overview")
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DriftSpacing.s32) {
                hero
                if !upcomingRenewals.isEmpty {
                    upcomingSection
                }
            }
            .padding(.vertical, DriftSpacing.s24)
        }
    }

    private var hero: some View {
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
        .padding(.horizontal, DriftSpacing.s16)
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: DriftSpacing.s12) {
            Text("Upcoming renewals")
                .font(DriftTypography.sectionTitle)
                .padding(.horizontal, DriftSpacing.s16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DriftSpacing.s12) {
                    ForEach(upcomingRenewals, id: \.persistentModelID) { subscription in
                        RenewalChip(subscription: subscription)
                    }
                }
                .padding(.horizontal, DriftSpacing.s16)
            }
        }
    }
}

private struct RenewalChip: View {
    let subscription: Subscription

    /// The amount actually billed at the next renewal (full cycle price, in the
    /// subscription's own currency) — not the normalized monthly figure, so a
    /// yearly plan shows what really lands on the card.
    private var renewalCharge: Decimal {
        subscription.billingCycle.cycleAmount(
            forMonthlyCost: subscription.monthlyCost,
            customCycleDays: subscription.customCycleDays
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DriftSpacing.s4) {
            Image(systemName: subscription.iconName)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(hex: subscription.customColor))
                .padding(.bottom, DriftSpacing.s4)

            Text(subscription.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Text(subscription.nextRenewalDate.formatted(.dateTime.month().day()))
                .font(DriftTypography.caption)
                .foregroundStyle(DriftTheme.subtleText)

            Text(renewalCharge, format: .currency(code: subscription.currencyCode))
                .font(DriftTypography.amount)
        }
        .padding(DriftSpacing.s12)
        .frame(width: 132, alignment: .leading)
        .background(DriftTheme.neutralFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
