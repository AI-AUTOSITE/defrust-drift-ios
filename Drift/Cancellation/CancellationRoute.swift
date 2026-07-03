import Foundation

/// Where a subscription's cancellation should send the user. Resolved from the
/// subscription's `billingChannel` (where they pay), NOT from the service name.
///
/// (Design: docs/cancellation-billing-channel-design.md)
enum CancellationRoute {
    /// Billed through a platform (Apple, Google, Amazon, Roku, …). Show that
    /// channel's guide — the service's own steps don't apply.
    case platform(BillingChannel)
    /// Billed directly by the service AND Drift has a bundled guide for it.
    case service(CancellationGuide)
    /// Billed directly but there's no bundled guide for this service — show a
    /// generic "cancel on the service's own site" message.
    case directGeneric
    /// Billing channel unknown — ask "Where did you subscribe?" first.
    case askChannel
}

/// Pure routing logic. No SwiftData writes, no UI — just decides which guide a
/// subscription should show. UI (Stage 2) calls `route(for:in:)` and renders.
enum CancellationRouter {

    static func route(for subscription: Subscription,
                      in store: CancellationGuideStore) -> CancellationRoute {
        switch subscription.billingChannel {
        case .none, .some(.unknown):
            // Channel not chosen yet: fall back to the service guide if we have
            // one (so this feature never hides a guide that used to show);
            // otherwise ask where they subscribed.
            if let guide = matchedGuide(for: subscription, in: store) {
                return .service(guide)
            }
            return .askChannel

        case .some(.directWeb):
            if let guide = matchedGuide(for: subscription, in: store) {
                return .service(guide)
            }
            return .directGeneric

        case .some(let channel):
            return .platform(channel)
        }
    }

    /// The bundled service guide for a subscription: matched by stored
    /// `serviceID` first, otherwise by an exact (case-insensitive) name match —
    /// same rule the detail screen already uses, kept in one place.
    static func matchedGuide(for subscription: Subscription,
                             in store: CancellationGuideStore) -> CancellationGuide? {
        if let serviceID = subscription.serviceID, let guide = store.guide(for: serviceID) {
            return guide
        }
        let name = subscription.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return store.allGuides.first {
            $0.serviceName.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
}
