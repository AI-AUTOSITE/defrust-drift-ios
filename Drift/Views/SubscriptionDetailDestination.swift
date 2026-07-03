//
//  SubscriptionDetailDestination.swift
//  Drift
//
//  Shared push destination for a tapped subscription, so the Overview cards and
//  the Monthly review both open the same detail screen (SubscriptionDetailView)
//  that the Subscriptions list uses. Because every screen reads the same
//  SwiftData store, an edit made here shows up everywhere automatically — there
//  is nothing extra to "sync".
//
//  Delete from these entry points is immediate (the Subscriptions list owns the
//  Undo banner, so a removal started elsewhere simply commits). It is deferred by
//  a short beat so the detail screen finishes popping before its model is
//  removed — otherwise the disappearing view could read a deleted object and
//  crash. Only a `PersistentIdentifier` (Sendable) crosses the await; the
//  SwiftData model never does.
//

import SwiftData
import SwiftUI
import WidgetKit

extension View {
    /// Registers `SubscriptionDetailView` as the push destination for a
    /// `Subscription` value. Pair with `NavigationLink(value: subscription)`
    /// inside the same `NavigationStack`.
    func subscriptionDetailDestination() -> some View {
        navigationDestination(for: Subscription.self) { subscription in
            SubscriptionDetailView(subscription: subscription) { target in
                deleteSubscription(target.persistentModelID)
            }
        }
    }
}

/// Deletes the subscription with the given id after a short delay, on its own
/// context, so the detail view has popped first.
private func deleteSubscription(_ objectID: PersistentIdentifier) {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(500))
        let context = ModelContext(SharedModelContainer.shared)
        guard let model = context.model(for: objectID) as? Subscription else { return }
        context.delete(model)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
