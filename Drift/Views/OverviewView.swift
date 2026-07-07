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
//  A "Monthly review" card opens the on-device review of which subscriptions
//  are worth cancelling (see MonthlyReviewView).
//

import Charts
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
    @State private var isShowingReview = false

    /// Paused subscriptions are excluded, as is any subscription currently in
    /// its swipe-delete undo window (so the total drops immediately, then comes
    /// back if the user taps Undo). Filtered in memory to sidestep SwiftData
    /// predicate quirks (and the set is tiny).
    private var activeSubscriptions: [Subscription] {
        subscriptions.filter {
            !$0.isPaused && !$0.isCanceled && $0.persistentModelID != deletionState.pendingID
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

    /// Monthly spend grouped by category (converted to the display currency),
    /// largest first. Subscriptions without a category fall under "Other".
    private var spendByCategory: [CategorySpend] {
        var totals: [String: (amount: Decimal, colorHex: String)] = [:]
        for subscription in activeSubscriptions {
            let converted = ExchangeRates.convert(
                subscription.monthlyCost,
                from: subscription.currencyCode,
                to: preferredCurrencyCode
            )
            let name = subscription.category?.name ?? "Other"
            let colorHex = subscription.category?.colorHex ?? "#8E8E93"
            let running = totals[name]?.amount ?? .zero
            totals[name] = (amount: running + converted, colorHex: colorHex)
        }
        return totals
            .map { CategorySpend(name: $0.key, amount: $0.value.amount, colorHex: $0.value.colorHex) }
            .sorted { $0.amount > $1.amount }
    }

    /// A little headroom past the largest bar so its amount label never clips.
    private var maxCategorySpend: Double {
        (spendByCategory.map(\.plottableAmount).max() ?? 1) * 1.3
    }

    private var categoryChartAccessibilityLabel: String {
        let parts = spendByCategory.map { item in
            "\(item.name), \(item.amount.formatted(.currency(code: preferredCurrencyCode))) per month"
        }
        return "Spending by category. " + parts.joined(separator: ". ")
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
            .subscriptionDetailDestination()
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
            .sheet(isPresented: $isShowingReview) {
                MonthlyReviewView()
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var canceledCount: Int {
        subscriptions.filter { $0.isCanceled }.count
    }

    /// Cumulative money reclaimed by canceling subscriptions: each canceled
    /// subscription's monthly cost (in the display currency) times how many
    /// months have passed since it was canceled. Grows over time.
    private var totalReclaimed: Decimal {
        let now = Date()
        return subscriptions
            .filter { $0.isCanceled }
            .reduce(Decimal.zero) { partial, sub in
                guard let canceledDate = sub.canceledDate, now > canceledDate else { return partial }
                let months = Decimal(now.timeIntervalSince(canceledDate) / (86_400 * 30.4375))
                let monthly = ExchangeRates.convert(
                    sub.monthlyCost,
                    from: sub.currencyCode,
                    to: preferredCurrencyCode
                )
                return partial + monthly * months
            }
    }

    /// The yearly amount no longer being paid — each canceled subscription's
    /// monthly cost (in the display currency) times 12. Meaningful the moment
    /// you cancel, unlike the slowly-accumulating `totalReclaimed`.
    private var annualReclaimed: Decimal {
        subscriptions
            .filter { $0.isCanceled }
            .reduce(Decimal.zero) { partial, sub in
                partial + ExchangeRates.convert(
                    sub.monthlyCost,
                    from: sub.currencyCode,
                    to: preferredCurrencyCode
                ) * 12
            }
    }

    /// Cumulative money reclaimed (display currency) at an arbitrary date.
    private func reclaimed(at date: Date, canceled: [Subscription]) -> Double {
        canceled.reduce(0.0) { partial, sub in
            guard let canceledDate = sub.canceledDate, date > canceledDate else { return partial }
            let months = date.timeIntervalSince(canceledDate) / (86_400 * 30.4375)
            let monthly = ExchangeRates.convert(
                sub.monthlyCost,
                from: sub.currencyCode,
                to: preferredCurrencyCode
            )
            return partial + NSDecimalNumber(decimal: monthly).doubleValue * months
        }
    }

    /// Real, accumulated reclaimed amount — one point per month from the first
    /// cancellation to today. Drawn as the solid line + filled area.
    private var reclaimedActualPoints: [ReclaimedPoint] {
        let canceled = subscriptions.filter { $0.isCanceled }
        guard let first = canceled.compactMap(\.canceledDate).min() else { return [] }
        let cal = Calendar.current
        let now = Date()
        var points: [ReclaimedPoint] = []
        var month = cal.dateInterval(of: .month, for: first)?.start ?? first
        var guardCount = 0
        while month < now, guardCount < 60 {
            points.append(ReclaimedPoint(date: month, amount: reclaimed(at: month, canceled: canceled), isProjected: false))
            month = cal.date(byAdding: .month, value: 1, to: month) ?? now
            guardCount += 1
        }
        points.append(ReclaimedPoint(date: now, amount: reclaimed(at: now, canceled: canceled), isProjected: false))
        return points
    }

    /// Projected trajectory at the current monthly rate, 12 months out. Starts
    /// at today's point (so it joins the solid line) and is drawn dashed to make
    /// clear it is an estimate, not money already reclaimed.
    private var reclaimedProjectedPoints: [ReclaimedPoint] {
        guard let bridge = reclaimedActualPoints.last else { return [] }
        let cal = Calendar.current
        let monthlyRate = NSDecimalNumber(decimal: annualReclaimed).doubleValue / 12.0
        var points: [ReclaimedPoint] = [bridge]
        for index in 1...12 {
            let date = cal.date(byAdding: .month, value: index, to: bridge.date) ?? bridge.date
            points.append(ReclaimedPoint(date: date, amount: bridge.amount + monthlyRate * Double(index), isProjected: true))
        }
        return points
    }

    private var savingsAccessibilityLabel: String {
        let annual = annualReclaimed.formatted(.currency(code: preferredCurrencyCode))
        let soFar = totalReclaimed.formatted(.currency(code: preferredCurrencyCode))
        let noun = canceledCount == 1 ? "subscription" : "subscriptions"
        return "Reclaimed \(annual) per year by canceling \(canceledCount) \(noun). \(soFar) so far."
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DriftSpacing.s32) {
                hero
                if canceledCount > 0 {
                    savingsSummary
                }
                reviewCard
                if !upcomingRenewals.isEmpty {
                    upcomingSection
                }
                if spendByCategory.count >= 2 {
                    byCategorySection
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

    /// Entry point to the monthly review. A single calm tap — the review runs
    /// on-device and works on every iPhone.
    private var reviewCard: some View {
        Button {
            isShowingReview = true
        } label: {
            HStack(spacing: DriftSpacing.s12) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DriftTheme.accent)

                VStack(alignment: .leading, spacing: DriftSpacing.s2) {
                    Text("Monthly review")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("See which subscriptions are worth a look")
                        .font(.subheadline)
                        .foregroundStyle(DriftTheme.subtleText)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: DriftSpacing.s8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DriftTheme.subtleText)
            }
            .padding(DriftSpacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DriftRadius.l, style: .continuous)
                    .fill(DriftTheme.neutralFill)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DriftSpacing.s16)
        .driftHaptic(.navigationLight, trigger: isShowingReview)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Monthly review. See which subscriptions are worth a look.")
        .accessibilityAddTraits(.isButton)
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
                        NavigationLink(value: subscription) {
                            RenewalChip(subscription: subscription)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens subscription details")
                    }
                }
                .padding(.horizontal, DriftSpacing.s16)
            }
        }
    }

    private var reclaimedChart: some View {
        Chart {
            ForEach(reclaimedActualPoints) { point in
                AreaMark(
                    x: .value("Month", point.date),
                    y: .value("Reclaimed", point.amount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DriftTheme.accent.opacity(0.25), DriftTheme.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Month", point.date),
                    y: .value("Reclaimed", point.amount)
                )
                .foregroundStyle(DriftTheme.accent)
                .interpolationMethod(.monotone)
            }

            ForEach(reclaimedProjectedPoints) { point in
                LineMark(
                    x: .value("Month", point.date),
                    y: .value("Reclaimed", point.amount)
                )
                .foregroundStyle(DriftTheme.accent.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .interpolationMethod(.monotone)
            }

            if let last = reclaimedActualPoints.last {
                PointMark(
                    x: .value("Month", last.date),
                    y: .value("Reclaimed", last.amount)
                )
                .foregroundStyle(DriftTheme.accent)
                .symbolSize(60)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Money reclaimed over time, rising and projected forward at the current pace.")
    }

    private var savingsSummary: some View {
        VStack(alignment: .leading, spacing: DriftSpacing.s4) {
            Text("Reclaimed")
                .font(DriftTypography.sectionTitle)
            Text("\(annualReclaimed.formatted(.currency(code: preferredCurrencyCode))) / year")
                .font(.title2.weight(.bold))
                .foregroundStyle(DriftTheme.accent)
            Text("\(totalReclaimed.formatted(.currency(code: preferredCurrencyCode))) reclaimed so far")
                .font(.footnote)
                .foregroundStyle(DriftTheme.subtleText)
            Text("by canceling \(canceledCount) \(canceledCount == 1 ? "subscription" : "subscriptions")")
                .font(.footnote)
                .foregroundStyle(DriftTheme.subtleText)

            reclaimedChart
                .padding(.top, DriftSpacing.s8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DriftSpacing.s16)
        .background(
            RoundedRectangle(cornerRadius: DriftRadius.l, style: .continuous)
                .fill(DriftTheme.neutralFill)
        )
        .padding(.horizontal, DriftSpacing.s16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(savingsAccessibilityLabel)
    }

    private var byCategorySection: some View {
        VStack(alignment: .leading, spacing: DriftSpacing.s12) {
            Text("By category")
                .font(DriftTypography.sectionTitle)
                .padding(.horizontal, DriftSpacing.s16)
                .accessibilityAddTraits(.isHeader)

            Chart(spendByCategory) { item in
                BarMark(
                    x: .value("Amount", item.plottableAmount),
                    y: .value("Category", item.name)
                )
                .foregroundStyle(Color.categoryTint(hex: item.colorHex))
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(item.amount, format: .currency(code: preferredCurrencyCode))
                        .font(DriftTypography.caption)
                        .foregroundStyle(DriftTheme.subtleText)
                }
            }
            .chartXScale(domain: 0...maxCategorySpend)
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: CGFloat(spendByCategory.count) * 44)
            .padding(DriftSpacing.s16)
            .background(
                RoundedRectangle(cornerRadius: DriftRadius.l, style: .continuous)
                    .fill(DriftTheme.neutralFill)
            )
            .padding(.horizontal, DriftSpacing.s16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(categoryChartAccessibilityLabel)
        }
    }
}

private struct ReclaimedPoint: Identifiable {
    let date: Date
    let amount: Double
    let isProjected: Bool

    var id: Date { date }
}

private struct CategorySpend: Identifiable {
    let name: String
    let amount: Decimal
    let colorHex: String

    var id: String { name }
    var plottableAmount: Double { NSDecimalNumber(decimal: amount).doubleValue }
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
