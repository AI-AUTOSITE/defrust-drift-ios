import Foundation

/// Plain, framework-free result of a monthly subscription review.
///
/// This is the type the app and every view consume. It is intentionally NOT
/// `@Generable`, so the rule-based fallback (Part 1B §5) and all UI work on the
/// iOS 17 deployment target. The on-device LLM path
/// (`OnDeviceFoundationModelsGateway`, added in the on-device phase) produces an
/// iOS-26-only `@Generable` value and maps it into this type — so callers never
/// see two different shapes.
///
/// (Resolves a spec inconsistency: Part 1B §4.2/§4.4 returned the `@Generable`
/// `MonthlyReviewResponse` directly, which cannot compile under iOS 17 even though
/// §5.5 requires the fallback to run there.)
///
/// `nonisolated` because the project builds with main-actor-by-default isolation
/// (Xcode 26 default); a plain data model must stay actor-agnostic so it can be
/// read from any context and used with key paths in SwiftUI.
nonisolated struct MonthlyReview: Equatable, Sendable {
    let suggestions: [ReviewSuggestion]
    /// Sum of `opportunityCostAnnualUSD` for suggestions whose action is `.cancel`.
    let totalPotentialSavingsUSD: Double
    /// Optional one-line, neutral summary.
    let summary: String?
}

/// One cancellation-review candidate.
nonisolated struct ReviewSuggestion: Equatable, Sendable, Identifiable {
    /// Matches the originating subscription's id so the UI can navigate to it.
    let id: UUID
    let subscriptionName: String
    /// 1 = high (clearly unused, expensive), 2 = medium, 3 = low.
    let priority: Int
    /// Cost over the next 12 months if kept unused (monthly cost × 12).
    let opportunityCostAnnualUSD: Double
    /// Short, neutral, plain-English explanation citing the concrete signal used.
    let rationale: String
    let suggestedAction: ReviewAction

    init(
        id: UUID = UUID(),
        subscriptionName: String,
        priority: Int,
        opportunityCostAnnualUSD: Double,
        rationale: String,
        suggestedAction: ReviewAction
    ) {
        self.id = id
        self.subscriptionName = subscriptionName
        self.priority = priority
        self.opportunityCostAnnualUSD = opportunityCostAnnualUSD
        self.rationale = rationale
        self.suggestedAction = suggestedAction
    }
}

/// Action Drift suggests for a subscription. String-backed so the on-device
/// model's string output (`@Guide(.anyOf([...]))`) maps in cleanly via
/// `ReviewAction(rawValue:)`.
nonisolated enum ReviewAction: String, Sendable {
    case review
    case cancel
    case keep
    case downgrade
}
