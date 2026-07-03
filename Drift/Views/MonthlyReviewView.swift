//
//  MonthlyReviewView.swift
//  Drift
//
//  The in-app monthly review — Drift's headline "which subscriptions are worth
//  cancelling?" screen. It runs the review engine over the user's active
//  subscriptions and lists the results: a suggested action, the yearly cost of
//  keeping each one, and a plain-English reason.
//
//  Presented as a sheet from Overview. The review runs through
//  `GatewayFactory.makeGateway()`, which today returns the deterministic
//  rule-based engine that works on every iOS 17+ device and never throws. The
//  on-device Apple Intelligence path can be slotted in later behind the same
//  factory and the same `MonthlyReview` result, so this screen does not change
//  when it lands — which is why the loading and failure states already exist.
//
//  All money is shown in the user's preferred display currency (matching
//  Overview): the engine works in USD, and `ExchangeRates.fromUSD` converts each
//  figure for display, so a mixed-currency library reads consistently.
//

import SwiftData
import SwiftUI

struct MonthlyReviewView: View {
    @Environment(\.dismiss) private var dismiss

    /// Preferred display currency, shared with Overview/Settings (device-local).
    @AppStorage("preferredCurrencyCode") private var preferredCurrencyCode = "USD"

    @Query(sort: \Subscription.name) private var subscriptions: [Subscription]

    @State private var phase: Phase = .loading
    /// Bumped to re-run the review (e.g. the "Try again" action).
    @State private var attempt = 0

    /// The review lifecycle. `failed` cannot occur on the rule-based path (it
    /// never throws); it is here so the Apple Intelligence path, which does throw
    /// `DriftAIError`, needs no change to this view.
    private enum Phase {
        case loading
        case loaded(MonthlyReview)
        case failed(DriftAIError)
    }

    /// Paused subscriptions are excluded so the review matches the live spend on
    /// Overview (a paused item is not currently billing).
    private var reviewable: [Subscription] {
        subscriptions.filter { !$0.isPaused }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    loadingView
                case .loaded(let review):
                    loadedView(review)
                case .failed:
                    failedView
                }
            }
            .navigationTitle("Monthly review")
            .navigationBarTitleDisplayMode(.inline)
            .subscriptionDetailDestination()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: attempt) { await runReview() }
    }

    // MARK: - Phase views

    private var loadingView: some View {
        VStack(spacing: DriftSpacing.s12) {
            ProgressView()
            Text("Reviewing your subscriptions…")
                .font(.subheadline)
                .foregroundStyle(DriftTheme.subtleText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func loadedView(_ review: MonthlyReview) -> some View {
        if review.suggestions.isEmpty {
            ContentUnavailableView(
                "Nothing to review",
                systemImage: "checkmark.circle",
                description: Text("No subscriptions look unused right now.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DriftSpacing.s24) {
                    savingsHeader(review)
                    suggestionsList(review)
                    disclaimer
                }
                .padding(.horizontal, DriftSpacing.s16)
                .padding(.vertical, DriftSpacing.s24)
            }
        }
    }

    private var failedView: some View {
        ContentUnavailableView {
            Label("Review unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Drift couldn't build a review just now. Please try again in a moment.")
        } actions: {
            Button("Try again") {
                phase = .loading
                attempt += 1
            }
        }
    }

    // MARK: - Loaded content pieces

    /// Yearly cost of the items Drift suggests cancelling, shown only when there
    /// is a concrete number. Framed as a calm upper bound ("up to … if you
    /// cancel") — never a promise.
    @ViewBuilder
    private func savingsHeader(_ review: MonthlyReview) -> some View {
        if review.totalPotentialSavingsUSD > 0 {
            let amount = displayAmount(fromUSD: review.totalPotentialSavingsUSD)
            VStack(alignment: .leading, spacing: DriftSpacing.s4) {
                Text("Up to \(amount.formatted(.currency(code: preferredCurrencyCode)))/yr")
                    .font(DriftTypography.sectionTitle)
                    .foregroundStyle(DriftTheme.success)
                Text("if you cancel the ones flagged below.")
                    .font(.subheadline)
                    .foregroundStyle(DriftTheme.subtleText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DriftSpacing.s16)
            .background(
                RoundedRectangle(cornerRadius: DriftRadius.l, style: .continuous)
                    .fill(DriftTheme.accentTinted)
            )
            .accessibilityElement(children: .combine)
        }
    }

    private func suggestionsList(_ review: MonthlyReview) -> some View {
        VStack(alignment: .leading, spacing: DriftSpacing.s12) {
            Text("Worth a look")
                .font(DriftTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: DriftSpacing.s8) {
                ForEach(review.suggestions) { suggestion in
                    suggestionRow(for: suggestion)
                }
            }
        }
    }

    /// Each suggestion links to its subscription's detail (edit, cancel
    /// reminder, cancel guide). If the subscription was removed since the review
    /// ran, the row shows without a link.
    @ViewBuilder
    private func suggestionRow(for suggestion: ReviewSuggestion) -> some View {
        let row = SuggestionRow(
            suggestion: suggestion,
            yearlyAmount: displayAmount(fromUSD: suggestion.opportunityCostAnnualUSD),
            currencyCode: preferredCurrencyCode
        )
        if let subscription = subscriptions.first(where: { $0.id == suggestion.id }) {
            NavigationLink(value: subscription) { row }
                .buttonStyle(.plain)
                .accessibilityHint("Opens subscription details")
        } else {
            row
        }
    }

    /// A quiet, honest note about how the review is produced. Reinforces the
    /// calm, on-device positioning without over-claiming.
    private var disclaimer: some View {
        Text("Based on how much each subscription costs and how recently you used it. Everything is worked out on your device.")
            .font(.footnote)
            .foregroundStyle(DriftTheme.subtleText)
            .padding(.top, DriftSpacing.s4)
    }

    // MARK: - Review execution

    private func displayAmount(fromUSD usd: Double) -> Decimal {
        ExchangeRates.fromUSD(usd, code: preferredCurrencyCode)
    }

    /// Builds Sendable snapshots on the main actor (reading SwiftData models),
    /// then hands only those value types to the gateway across the await —
    /// SwiftData `@Model` objects must never cross an async boundary.
    private func makeSnapshots() -> [SubscriptionSnapshot] {
        reviewable.map { sub in
            SubscriptionSnapshot(
                id: sub.id,
                name: sub.name,
                monthlyCostUSD: ExchangeRates.toUSD(sub.monthlyCost, code: sub.currencyCode),
                currencyCode: sub.currencyCode,
                lastUsedDate: sub.lastUsedDate,
                frequencyTag: sub.frequencyTag ?? "never",
                startDate: sub.startDate,
                category: sub.category?.name
            )
        }
    }

    private func runReview() async {
        let snapshots = makeSnapshots()
        let gateway = GatewayFactory.makeGateway()
        do {
            let review = try await gateway.generateMonthlyReview(for: snapshots)
            phase = .loaded(review)
        } catch let error as DriftAIError {
            phase = .failed(error)
        } catch {
            phase = .failed(.unknown(error.localizedDescription))
        }
    }
}

// MARK: - Suggestion row

private struct SuggestionRow: View {
    let suggestion: ReviewSuggestion
    let yearlyAmount: Decimal
    let currencyCode: String

    private var yearlyText: String {
        "\(yearlyAmount.formatted(.currency(code: currencyCode)))/yr"
    }

    /// One combined VoiceOver phrase instead of four separate stops (name,
    /// action, amount, reason), matching the row pattern used elsewhere.
    private var accessibilityText: String {
        let action = ActionStyle(action: suggestion.suggestedAction).label
        let yearly = yearlyAmount.formatted(.currency(code: currencyCode))
        return "\(suggestion.subscriptionName). \(action). \(yearly) per year. \(suggestion.rationale)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DriftSpacing.s8) {
            HStack(alignment: .firstTextBaseline) {
                Text(suggestion.subscriptionName)
                    .font(.headline)
                Spacer(minLength: DriftSpacing.s8)
                Text(yearlyText)
                    .font(DriftTypography.amount)
                    .foregroundStyle(DriftTheme.subtleText)
            }
            ActionChip(action: suggestion.suggestedAction)
            Text(suggestion.rationale)
                .font(.subheadline)
                .foregroundStyle(DriftTheme.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DriftSpacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DriftRadius.l, style: .continuous)
                .fill(DriftTheme.neutralFill)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

// MARK: - Action styling

/// Presentation for a suggested action: a short label, an icon, and a calm tint.
/// Meaning is carried by all three, never by color alone (WCAG 1.4.1).
private struct ActionStyle {
    let label: String
    let symbol: String
    let tint: Color

    init(action: ReviewAction) {
        switch action {
        case .cancel:
            label = "Consider cancelling"
            symbol = "scissors"
            tint = DriftTheme.cautionCalm
        case .review:
            label = "Take a look"
            symbol = "magnifyingglass"
            tint = DriftTheme.warningSoft
        case .downgrade:
            label = "Cheaper tier?"
            symbol = "arrow.down.circle"
            tint = DriftTheme.accentDeep
        case .keep:
            label = "Keep for now"
            symbol = "checkmark.circle"
            tint = DriftTheme.success
        }
    }
}

private struct ActionChip: View {
    let action: ReviewAction

    private var style: ActionStyle { ActionStyle(action: action) }

    var body: some View {
        HStack(spacing: DriftSpacing.s4) {
            Image(systemName: style.symbol)
                .symbolRenderingMode(.hierarchical)
            Text(style.label)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(style.tint)
        .padding(.horizontal, DriftSpacing.s8)
        .padding(.vertical, DriftSpacing.s4)
        .background(Capsule().fill(style.tint.opacity(0.14)))
        .accessibilityHidden(true)
    }
}
