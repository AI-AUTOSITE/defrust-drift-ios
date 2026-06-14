import Foundation
import NaturalLanguage

/// Deterministic, fully on-device monthly review that needs no LLM.
///
/// Works on the iOS 17 deployment target and for every user (Free included), and
/// returns the same `MonthlyReview` shape as the on-device path, so the UI is
/// identical. Pure functions → trivially unit-testable and snapshot-stable
/// (Part 1B §5).
///
/// `nonisolated` (project builds with main-actor-by-default isolation): the
/// scoring is pure and stateless, so it should run on any executor — including
/// off the main thread for large subscription lists. Members live in the type
/// body (not extensions) so the type's `nonisolated` applies to them with no
/// ambiguity.
nonisolated struct RuleBasedFallbackGateway: FoundationModelsGateway {
    var isOnDeviceLLMAvailable: Bool { false }

    func generateMonthlyReview(for snapshots: [SubscriptionSnapshot]) async throws -> MonthlyReview {
        let overlapping = Self.detectOverlappingServices(in: snapshots)

        let ranked = snapshots
            .map { ScoredSnapshot(snapshot: $0, score: Self.score($0)) }
            .sorted { $0.score > $1.score }
            .prefix(5)

        let suggestions = ranked.map { entry -> ReviewSuggestion in
            let hasOverlap = overlapping.contains(entry.snapshot.id)
            let action = Self.action(for: entry.snapshot, score: entry.score, hasOverlap: hasOverlap)
            return ReviewSuggestion(
                id: entry.snapshot.id,
                subscriptionName: entry.snapshot.name,
                priority: Self.priority(for: entry.score),
                opportunityCostAnnualUSD: entry.snapshot.monthlyCostUSD * 12,
                rationale: Self.rationale(for: entry.snapshot, action: action, hasOverlap: hasOverlap),
                suggestedAction: action
            )
        }

        let savings = suggestions
            .filter { $0.suggestedAction == .cancel }
            .reduce(0.0) { $0 + $1.opportunityCostAnnualUSD }

        return MonthlyReview(
            suggestions: suggestions,
            totalPotentialSavingsUSD: savings,
            summary: suggestions.isEmpty
                ? "No subscriptions look unused this month."
                : "Drift found \(suggestions.count) candidates to review based on usage and cost."
        )
    }

    // MARK: - Scoring

    /// Higher multiplier == less-used tag == more likely a cancellation candidate.
    static let frequencyMultiplier: [String: Double] = [
        "daily": 0.1,
        "weekly": 0.3,
        "monthly": 0.7,
        "rarely": 1.5,
        "never": 2.5
    ]

    static func score(_ snapshot: SubscriptionSnapshot) -> Double {
        let anchor = snapshot.lastUsedDate ?? snapshot.startDate
        let daysSinceUse = max(0, Calendar.current.dateComponents([.day], from: anchor, to: Date()).day ?? 0)
        var value = Double(daysSinceUse) * 0.5
        value += snapshot.monthlyCostUSD * 1.5
        value *= frequencyMultiplier[snapshot.frequencyTag] ?? 1.0
        return value
    }

    static func priority(for score: Double) -> Int {
        switch score {
        case 60...: return 1
        case 25..<60: return 2
        default: return 3
        }
    }

    static func action(for snapshot: SubscriptionSnapshot, score: Double, hasOverlap: Bool) -> ReviewAction {
        if hasOverlap, snapshot.monthlyCostUSD > 8 { return .cancel }
        switch score {
        case 80...: return .cancel
        case 40..<80: return .review
        case 15..<40: return .downgrade
        default: return .keep
        }
    }

    static func rationale(for snapshot: SubscriptionSnapshot, action: ReviewAction, hasOverlap: Bool) -> String {
        let days = snapshot.lastUsedDate.map {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
        } ?? 365
        let cost = String(format: "$%.2f/mo", snapshot.monthlyCostUSD)
        let overlapNote = hasOverlap ? " You also pay for a similar service." : ""
        switch action {
        case .cancel:
            return "Not used in \(days) days at \(cost).\(overlapNote)"
        case .review:
            return "Used infrequently (\(snapshot.frequencyTag)) at \(cost). Confirm it still earns its keep."
        case .downgrade:
            return "Tagged \(snapshot.frequencyTag) at \(cost). A cheaper tier may cover your usage."
        case .keep:
            return "Used recently. Keep for now."
        }
    }

    // MARK: - Overlapping / duplicate service detection

    /// Flags subscriptions that look like overlapping or duplicate services.
    ///
    /// Primary signal: two or more subscriptions sharing a category (needs no
    /// embedding). Secondary signal, only when an English word embedding is
    /// available: similar names. Proper nouns ("Hulu") are often missing from the
    /// embedding vocabulary, so the category signal is primary and the vector
    /// distance is auxiliary (Part 1B §5.4).
    ///
    /// Note: the category pass runs before the embedding guard, so a missing
    /// embedding no longer skips overlap detection entirely (a deviation from the
    /// spec sample, which returned early).
    static func detectOverlappingServices(in snapshots: [SubscriptionSnapshot]) -> Set<UUID> {
        var overlapping: Set<UUID> = []

        let byCategory = Dictionary(grouping: snapshots) { $0.category ?? "Other" }
        for (_, group) in byCategory where group.count >= 2 {
            for snapshot in group { overlapping.insert(snapshot.id) }
        }

        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            return overlapping
        }
        for i in snapshots.indices {
            for j in (i + 1)..<snapshots.count {
                let distance = embedding.distance(
                    between: snapshots[i].name.lowercased(),
                    and: snapshots[j].name.lowercased()
                )
                if distance < 0.9 {
                    overlapping.insert(snapshots[i].id)
                    overlapping.insert(snapshots[j].id)
                }
            }
        }
        return overlapping
    }
}

// MARK: - Ranking helper

private nonisolated struct ScoredSnapshot {
    let snapshot: SubscriptionSnapshot
    let score: Double
}
