import Foundation

/// Abstraction over "produce a monthly subscription review".
///
/// Two concrete implementations conform to this:
/// - `RuleBasedFallbackGateway` (sibling file): deterministic, works on the iOS 17
///   deployment target and for every user (Free included). **Implemented now.**
/// - `OnDeviceFoundationModelsGateway` (iOS 26+, added in the on-device phase):
///   runs Apple Intelligence and maps its `@Generable` output into `MonthlyReview`.
///
/// Both return the same plain `MonthlyReview`, so the UI never branches on which
/// path produced the result.
///
/// Lives in the app target for now; the protocol-based design lets it move to
/// the shared `DefrustKit` package unchanged when that package is vendored.
protocol FoundationModelsGateway: Sendable {
    /// `true` only when a real on-device LLM is available and will be used.
    nonisolated var isOnDeviceLLMAvailable: Bool { get }

    /// Produce a review for the given snapshots. The on-device path throws
    /// `DriftAIError`; the rule-based path never throws.
    nonisolated func generateMonthlyReview(for snapshots: [SubscriptionSnapshot]) async throws -> MonthlyReview

    /// Warm up the model if (and only if) one is available. No-op otherwise.
    /// Call ~1s before `generateMonthlyReview` for best latency.
    nonisolated func prewarmIfPossible()
}

extension FoundationModelsGateway {
    /// Default no-op so paths without an LLM need not implement it.
    nonisolated func prewarmIfPossible() {}
}

/// Immutable, framework-free snapshot of a subscription, sized for AI/scoring.
///
/// Deliberately decoupled from the SwiftData `Subscription` model so the gateway
/// depends on neither SwiftData nor FoundationModels. The Overview view model
/// builds these (converting `Decimal` cost to a USD `Double`) when it runs a
/// review. Note `frequencyTag` is non-optional here; map `Subscription`'s optional
/// tag with `?? "never"` at the call site.
nonisolated struct SubscriptionSnapshot: Sendable, Hashable {
    let id: UUID
    let name: String
    let monthlyCostUSD: Double
    let currencyCode: String
    let lastUsedDate: Date?
    /// "daily" / "weekly" / "monthly" / "rarely" / "never".
    let frequencyTag: String
    let startDate: Date
    let category: String?

    init(
        id: UUID,
        name: String,
        monthlyCostUSD: Double,
        currencyCode: String,
        lastUsedDate: Date? = nil,
        frequencyTag: String,
        startDate: Date,
        category: String? = nil
    ) {
        self.id = id
        self.name = name
        self.monthlyCostUSD = monthlyCostUSD
        self.currencyCode = currencyCode
        self.lastUsedDate = lastUsedDate
        self.frequencyTag = frequencyTag
        self.startDate = startDate
        self.category = category
    }
}

/// Errors surfaced by the on-device review path (Part 1B §4.7). The rule-based
/// path never throws these; it always returns a `MonthlyReview`.
///
/// `unknown` carries a `String` rather than `any Error` so the enum stays
/// `Sendable` under Swift 6 strict concurrency.
nonisolated enum DriftAIError: Error, Sendable, Equatable {
    case modelUnavailable
    case contextWindowExceeded
    case guardrailBlocked
    case schemaIncompatible
    case languageUnsupported
    case decodingFailed
    case busy
    case modelDownloading
    case refused(String)
    case unknown(String)
}

/// Chooses the gateway for the current device.
///
/// On the iOS 17–25 deployment range, and on devices without Apple Intelligence,
/// this returns the deterministic rule-based gateway. The on-device LLM branch is
/// wired in when `OnDeviceFoundationModelsGateway` lands (on-device phase, iOS 26+).
enum GatewayFactory {
    nonisolated static func makeGateway() -> any FoundationModelsGateway {
        // TODO(on-device phase): once OnDeviceFoundationModelsGateway exists, return
        // it behind `if #available(iOS 26.0, *), ModelAvailabilityProbe.current() == .ready`.
        RuleBasedFallbackGateway()
    }
}
