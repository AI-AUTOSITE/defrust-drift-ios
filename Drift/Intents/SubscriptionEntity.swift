import AppIntents
import Foundation
import SwiftData

/// Lightweight projection of a `Subscription` for Siri / Shortcuts / Spotlight.
/// Identified by `subscription.id` — the same stable UUID used for notification
/// requests and `drift://` links — so resolving an entity back to its model is a
/// simple id lookup.
struct SubscriptionEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Subscription",
            numericFormat: "\(placeholder: .int) subscriptions"
        )
    }

    static var defaultQuery = SubscriptionQuery()

    var id: UUID
    var name: String
    var monthlyCost: Double
    var currencyCode: String
    var nextRenewalDate: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(monthlyCost.formatted(.currency(code: currencyCode))) / month"
        )
    }
}

extension SubscriptionEntity {
    init(from sub: Subscription) {
        self.id = sub.id
        self.name = sub.name
        self.monthlyCost = NSDecimalNumber(decimal: sub.monthlyCost).doubleValue
        self.currencyCode = sub.currencyCode
        self.nextRenewalDate = sub.nextRenewalDate
    }
}

/// Resolves `SubscriptionEntity` values for the system. Filtering is done in memory
/// (the dataset is tens of rows at most) so we avoid UUID/`contains` predicate quirks.
struct SubscriptionQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SubscriptionEntity] {
        let context = ModelContext(SharedModelContainer.shared)
        let ids = Set(identifiers)
        let all = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        return all
            .filter { ids.contains($0.id) }
            .map(SubscriptionEntity.init(from:))
    }

    @MainActor
    func suggestedEntities() async throws -> [SubscriptionEntity] {
        let context = ModelContext(SharedModelContainer.shared)
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate<Subscription> { !$0.isPaused },
            sortBy: [SortDescriptor(\.name)]
        )
        let active = (try? context.fetch(descriptor)) ?? []
        return active.prefix(20).map(SubscriptionEntity.init(from:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [SubscriptionEntity] {
        let context = ModelContext(SharedModelContainer.shared)
        let all = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        return all
            .filter { $0.name.localizedStandardContains(string) }
            .map(SubscriptionEntity.init(from:))
    }
}
