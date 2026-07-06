import Foundation
import SwiftData
import Testing
@testable import Drift

// `Category` also exists in a system framework, so the unqualified name is
// ambiguous inside the test module (the app module wins via its own typealias).
// This local alias pins it to Drift's model.
private typealias Category = DriftSchemaV1.Category

@Suite("DriftSchemaV1 (in-memory)")
@MainActor
struct DriftSchemaV1Tests {

    /// Boots the same way DriftApp will — versioned schema + migration plan —
    /// but in memory. Real CloudKit sync is verified manually on two devices (1C-2 §14.5).
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: DriftSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: DriftMigrationPlan.self,
            configurations: [configuration]
        )
    }

    @Test("Container boots with versioned schema and migration plan")
    func containerBoots() throws {
        _ = try makeContainer()
    }

    @Test("Subscription round-trips through insert, save, and fetch")
    func subscriptionRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cost = try #require(Decimal(string: "15.99"))

        let netflix = Subscription(
            name: "Netflix",
            monthlyCost: cost,
            currencyCode: "USD",
            billingCycle: .monthly
        )
        context.insert(netflix)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Subscription>())
        let sub = try #require(fetched.first)
        #expect(fetched.count == 1)
        #expect(sub.name == "Netflix")
        #expect(sub.monthlyCost == cost) // pure Decimal comparison
        #expect(sub.currencyCode == "USD")
        #expect(sub.billingCycle == .monthly)
    }

    @Test("billingCycle maps to its raw string and unknown raw falls back to monthly")
    func billingCycleMapping() {
        let sub = Subscription(name: "iCloud+", billingCycle: .yearly)
        #expect(sub.billingCycleRaw == "yearly")

        sub.billingCycle = .weekly
        #expect(sub.billingCycleRaw == "weekly")

        sub.billingCycleRaw = "fortnightly" // a future, unknown case
        #expect(sub.billingCycle == .monthly)
    }

    @Test("Subscription→UsageRecord relationship wires both sides")
    func usageRelationship() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let sub = Subscription(name: "Spotify")
        context.insert(sub)
        let first = UsageRecord(subscription: sub)
        let second = UsageRecord(subscription: sub, wasUsed: false)
        context.insert(first)
        context.insert(second)
        try context.save()

        #expect(sub.unwrappedUsageRecords.count == 2)
        #expect(first.subscription === sub)
    }

    @Test("Deleting a Subscription cascades to usage records and notifications")
    func cascadeDelete() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let sub = Subscription(name: "Gym")
        context.insert(sub)
        let usage = UsageRecord(subscription: sub)
        let notification = RenewalNotification(subscription: sub)
        context.insert(usage)
        context.insert(notification)
        try context.save()
        #expect(notification.daysBeforeRenewal == 3) // default preset

        context.delete(sub)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Subscription>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UsageRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RenewalNotification>()) == 0)
    }

    @Test("Deleting a Category nullifies but keeps its subscriptions")
    func categoryNullify() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let streaming = Category(name: "Streaming")
        let sub = Subscription(name: "Netflix")
        context.insert(streaming)
        context.insert(sub)
        sub.category = streaming
        try context.save()

        context.delete(streaming)
        try context.save()

        let subs = try context.fetch(FetchDescriptor<Subscription>())
        #expect(subs.count == 1)
        #expect(subs.first?.category == nil)
    }

    @Test("Category.seedIfNeeded seeds the defaults exactly once")
    func seedIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext

        Category.seedIfNeeded(in: context)
        #expect(try context.fetchCount(FetchDescriptor<Category>()) == Category.defaultPresetCount)

        Category.seedIfNeeded(in: context) // second call is a no-op
        #expect(try context.fetchCount(FetchDescriptor<Category>()) == Category.defaultPresetCount)

        let bySortOrder = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)])
        let seeded = try context.fetch(bySortOrder)
        #expect(seeded.first?.name == "Streaming")
        #expect(seeded.last?.name == "Other")
    }

    @Test("Predicate filters out paused subscriptions")
    func predicateFiltersPaused() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let active = Subscription(name: "Spotify")
        let paused = Subscription(name: "Gym")
        paused.isPaused = true
        context.insert(active)
        context.insert(paused)
        try context.save()

        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate<Subscription> { !$0.isPaused },
            sortBy: [SortDescriptor(\.name)]
        )
        let result = try context.fetch(descriptor)
        #expect(result.map(\.name) == ["Spotify"])
    }
}
