//
//  OverviewView.swift
//  Drift
//
//  At-a-glance monthly state. The hero total is converted into the user's
//  preferred display currency (set in Settings, reached via the gearshape);
//  individual subscriptions still show the amount actually billed, so the
//  per-item figures stay exact. An "Upcoming renewals" rail shows what renews
//  in the next 30 days. Charts, "vs. last month" and the Pro savings card
//  come later.
//

import SwiftData
import SwiftUI

struct OverviewView: View {
    @Environment(DeletionState.self) private var deletionState
    @Query(sort: \Subscription.nextRenewalDate)
    private var subscriptions: [Subscription]

    /// Currency the hero total is shown in. Device-local (UserDefaults), shared
    /// with Settings; defaults to USD so the total reads exactly as before until
    /// the user changes it.
    @AppStorage("preferredCurrencyCode") private var preferredCurrencyCode = "USD"

    @State private var isShowingSettings = false

    /// Paused subscriptions are excluded, as is any subscription currently in
    /// its swipe-delete undo window (so the total drops immediately, then comes
    /// back if the user taps Undo). Filtered in memory to sidestep SwiftData
    /// predicate quirks (and the set is tiny).
    private var activeSubscriptions: [Subscription] {
        subscriptions.filter {
            !$0.isPaused && $0.persistentModelID != deletionState.pendingID
        }
    }

    /// Sum of every active subscription, each converted from its own currency
    /// into the preferred display currency so mixed-currency totals are correct.
    /// Only this aggregate is converted — individual rows keep their own billed
    /// currency (Part 1B §11.2).
    private var monthlyTotal: Decimal {
        activeSubscriptions.reduce(Decimal.zero) { partial, subscription in
            partial + ExchangeRates.convert(
                subscription.monthlyCost,
                from: subscription.currencyCode,
                to: preferredCurrencyCode
            )
        }
    }

    private var yearlyTotal: Decimal {
        monthlyTotal * 12
    }

    /// A single spoken summary of the screen's headline numbers, so VoiceOver
    /// reads "This month, $74.12. $889.44 per year. 5 active subscriptions." in
    /// one stop instead of four separate fragments (label, total, year, count).
    private var heroAccessibilityLabel: String {
        let monthly = monthlyTotal.formatted(.currency(code: preferredCurrencyCode))
        let yearly = yearlyTotal.formatted(.currency(code: preferredCurrencyCode))
        let count = activeSubscriptions.count
        let unit = count == 1 ? "subscription" : "subscriptions"
        return "This month, \(monthly). \(yearly) per year. \(count) active \(unit)."
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .presentationDragIndicator(.visible)
            }
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

            Text(monthlyTotal, format: .currency(code: preferredCurrencyCode))
                .font(DriftTypography.hero)
                .minimumScaleFactor(0.6)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("\(yearlyTotal.formatted(.currency(code: preferredCurrencyCode))) / year")
                .font(DriftTypography.caption)
                .foregroundStyle(DriftTheme.subtleText)

            Text("\(activeSubscriptions.count) active")
                .font(DriftTypography.caption)
                .foregroundStyle(DriftTheme.subtleText)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DriftSpacing.s16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel)
        .accessibilityAddTraits(.isSummaryElement)
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: DriftSpacing.s12) {
            Text("Upcoming renewals")
                .font(DriftTypography.sectionTitle)
                .padding(.horizontal, DriftSpacing.s16)
                .accessibilityAddTraits(.isHeader)

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

    /// Chip width scales with the user's text size so the name, date, and amount
    /// have room at larger Dynamic Type sizes instead of clipping in a fixed box.
    /// (Full Dynamic Type reflow across the app is handled in a later pass.)
    @ScaledMetric private var chipWidth: CGFloat = 132

    /// The amount actually billed at the next renewal (full cycle price, in the
    /// subscription's own currency) — not the normalized monthly figure, so a
    /// yearly plan shows what really lands on the card.
    private var renewalCharge: Decimal {
        subscription.billingCycle.cycleAmount(
            forMonthlyCost: subscription.monthlyCost,
            customCycleDays: subscription.customCycleDays
        )
    }

    /// One coherent VoiceOver phrase ("PulseFit, renews June 2, $19.99") instead
    /// of four separate stops (icon, name, date, amount), matching the rows.
    private var accessibilityDescription: String {
        let date = subscription.nextRenewalDate.formatted(.dateTime.month(.wide).day())
        let charge = renewalCharge.formatted(.currency(code: subscription.currencyCode))
        return "\(subscription.name), renews \(date), \(charge)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DriftSpacing.s4) {
            Image(systemName: subscription.iconName)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.categoryTint(hex: subscription.customColor))
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
        .frame(width: chipWidth, alignment: .leading)
        .background(DriftTheme.neutralFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}
