import Foundation
import Testing
@testable import Drift

@Suite("RuleBasedFallbackGateway — deterministic review")
struct RuleBasedFallbackGatewayTests {

    /// Build a snapshot with sensible defaults; each test overrides what it cares about.
    private func snapshot(
        name: String = "Service",
        monthlyCostUSD: Double = 10,
        frequency: String = "monthly",
        daysSinceLastUse: Int? = 30,
        category: String? = nil
    ) -> SubscriptionSnapshot {
        let now = Date()
        let lastUsed = daysSinceLastUse.map {
            Calendar.current.date(byAdding: .day, value: -$0, to: now) ?? now
        }
        return SubscriptionSnapshot(
            id: UUID(),
            name: name,
            monthlyCostUSD: monthlyCostUSD,
            currencyCode: "USD",
            lastUsedDate: lastUsed,
            frequencyTag: frequency,
            startDate: Calendar.current.date(byAdding: .day, value: -400, to: now) ?? now,
            category: category
        )
    }

    @Test("Empty input yields no suggestions and a calm summary")
    func emptyInput() async throws {
        let review = try await RuleBasedFallbackGateway().generateMonthlyReview(for: [])
        #expect(review.suggestions.isEmpty)
        #expect(review.totalPotentialSavingsUSD == 0)
        #expect(review.summary == "No subscriptions look unused this month.")
    }

    @Test("At most five suggestions, ordered by score (priority ascending)")
    func capsAtFiveOrdered() async throws {
        let snaps = (1...8).map {
            snapshot(name: "S\($0)", monthlyCostUSD: Double($0), frequency: "never",
                     daysSinceLastUse: 200, category: "C\($0)")
        }
        let review = try await RuleBasedFallbackGateway().generateMonthlyReview(for: snaps)
        #expect(review.suggestions.count == 5)
        // Highest monthly cost (S8) scores highest under "never" + long disuse.
        #expect(review.suggestions.first?.subscriptionName == "S8")
        let priorities = review.suggestions.map(\.priority)
        #expect(priorities == priorities.sorted())
    }

    @Test("Opportunity cost is always monthly × 12")
    func opportunityCostIsAnnual() async throws {
        let review = try await RuleBasedFallbackGateway()
            .generateMonthlyReview(for: [snapshot(monthlyCostUSD: 9.99)])
        #expect(review.suggestions.first?.opportunityCostAnnualUSD == 9.99 * 12)
    }

    @Test("Expensive, never-used subscription is flagged to cancel")
    func expensiveUnusedCancels() async throws {
        let snap = snapshot(name: "GhostGym", monthlyCostUSD: 60, frequency: "never", daysSinceLastUse: 300)
        let review = try await RuleBasedFallbackGateway().generateMonthlyReview(for: [snap])
        let suggestion = try #require(review.suggestions.first)
        #expect(suggestion.suggestedAction == .cancel)
        #expect(suggestion.priority == 1)
        #expect(review.totalPotentialSavingsUSD == 60 * 12)
        #expect(suggestion.rationale.contains("$60.00/mo"))
        // The suggestion id mirrors the originating snapshot id (for UI navigation).
        #expect(suggestion.id == snap.id)
    }

    @Test("Recently used subscription is kept")
    func recentlyUsedKept() async throws {
        let snap = snapshot(name: "DailyDriver", monthlyCostUSD: 5, frequency: "daily", daysSinceLastUse: 1)
        let review = try await RuleBasedFallbackGateway().generateMonthlyReview(for: [snap])
        let suggestion = try #require(review.suggestions.first)
        #expect(suggestion.suggestedAction == .keep)
        #expect(suggestion.priority == 3)
        #expect(review.totalPotentialSavingsUSD == 0)
    }

    @Test("Two subscriptions sharing a category are flagged as overlapping",
          arguments: ["Streaming"])
    func sameCategoryOverlap(category: String) {
        let alpha = snapshot(name: "Alpha", category: category)
        let beta = snapshot(name: "Beta", category: category)
        let overlapping = RuleBasedFallbackGateway.detectOverlappingServices(in: [alpha, beta])
        #expect(overlapping.contains(alpha.id))
        #expect(overlapping.contains(beta.id))
    }

    @Test("A lone subscription is not overlapping")
    func loneNotOverlap() {
        let solo = snapshot(name: "Solo", category: "SaaS")
        let overlapping = RuleBasedFallbackGateway.detectOverlappingServices(in: [solo])
        #expect(overlapping.isEmpty)
    }

    @Test("Priority thresholds map score to band")
    func priorityBands() {
        #expect(RuleBasedFallbackGateway.priority(for: 70) == 1)
        #expect(RuleBasedFallbackGateway.priority(for: 40) == 2)
        #expect(RuleBasedFallbackGateway.priority(for: 10) == 3)
    }
}

// MARK: - Protocol seam

/// Deterministic stand-in used to test code that depends on the gateway
/// without invoking scoring or an LLM.
nonisolated struct MockFoundationModelsGateway: FoundationModelsGateway {
    var isOnDeviceLLMAvailable: Bool
    var stubbedReview: MonthlyReview

    func generateMonthlyReview(for snapshots: [SubscriptionSnapshot]) async throws -> MonthlyReview {
        stubbedReview
    }
}

@Suite("FoundationModelsGateway — protocol seam")
struct FoundationModelsGatewaySeamTests {

    @Test("Mock returns exactly the injected review")
    func mockReturnsInjected() async throws {
        let stub = MonthlyReview(
            suggestions: [
                ReviewSuggestion(subscriptionName: "X", priority: 1,
                                 opportunityCostAnnualUSD: 120, rationale: "stub",
                                 suggestedAction: .cancel)
            ],
            totalPotentialSavingsUSD: 120,
            summary: "stub"
        )
        let gateway: any FoundationModelsGateway =
            MockFoundationModelsGateway(isOnDeviceLLMAvailable: true, stubbedReview: stub)
        let review = try await gateway.generateMonthlyReview(for: [])
        #expect(review == stub)
        #expect(gateway.isOnDeviceLLMAvailable)
    }

    @Test("Factory returns a working gateway")
    func factoryReturnsGateway() async throws {
        let gateway = GatewayFactory.makeGateway()
        // On CI / simulators without Apple Intelligence this is the rule-based path.
        #expect(gateway.isOnDeviceLLMAvailable == false)
        let review = try await gateway.generateMonthlyReview(for: [])
        #expect(review.suggestions.isEmpty)
    }
}
