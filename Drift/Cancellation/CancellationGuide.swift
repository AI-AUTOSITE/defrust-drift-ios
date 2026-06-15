import Foundation

/// One service's plain-text cancellation guide, decoded from
/// `cancellation_guides_v1.json`. `id` is kebab-case and maps 1:1 to
/// `Subscription.serviceID`. A `nil` `primaryCancelURL` means the service is
/// Apple-billed (cancellable only through the App Store subscriptions sheet).
struct CancellationGuide: Codable, Identifiable, Hashable {
    let id: String
    let serviceName: String
    let category: String
    let regionAvailability: [String]
    let primaryCancelURL: String?
    let appleBilledOption: Bool
    let steps: [CancellationStep]
    let estimatedTimeMinutes: Int
    let lastVerifiedDate: String
    let darkPatternScore: Int
    let warningNote: String?
    let notes: String?
}

struct CancellationStep: Codable, Hashable {
    let order: Int
    let action: String
    let supportingNote: String?
}
