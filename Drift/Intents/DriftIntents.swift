import AppIntents
import Foundation
import SwiftData

/// "What's my total monthly spend on Drift?"
struct MonthlySpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Show monthly spend"
    static var description = IntentDescription("Returns your current monthly subscription total.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(SharedModelContainer.shared)
        let descriptor = FetchDescriptor<Subscription>(predicate: #Predicate<Subscription> { !$0.isPaused })
        let subs = (try? context.fetch(descriptor)) ?? []
        let totalUSD = subs.reduce(0.0) { $0 + ExchangeRates.toUSD($1.monthlyCost, code: $1.currencyCode) }
        let formatted = totalUSD.formatted(.currency(code: "USD"))
        return .result(dialog: "Your subscriptions cost \(formatted) per month.")
    }
}

/// "Add a subscription to Drift" — opens the app at the add flow, carrying any captured
/// name / cost through the App Group so the app can prefill (consumed in the UI phase).
struct AddSubscriptionIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a subscription"
    static var description = IntentDescription("Opens Drift to add a new subscription.")
    static var openAppWhenRun = true

    @Parameter(title: "Name") var name: String?
    @Parameter(title: "Monthly cost (USD)") var monthlyCostUSD: Double?

    func perform() async throws -> some IntentResult {
        // App Group hand-off: the app reads and clears these on foreground (UI phase).
        // No-op until the App Group entitlement is configured (with the widget).
        let defaults = UserDefaults(suiteName: "group.com.defrust.drift")
        defaults?.set(name, forKey: "pendingAdd.name")
        defaults?.set(monthlyCostUSD, forKey: "pendingAdd.monthlyCostUSD")
        return .result()
    }
}

/// "Mark Netflix as used in Drift"
struct MarkSubscriptionUsedIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark subscription as used"
    static var description = IntentDescription("Logs that you used a subscription today.")
    static var openAppWhenRun = false

    @Parameter(title: "Subscription") var subscription: SubscriptionEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(SharedModelContainer.shared)
        let targetID = subscription.id
        let all = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        guard let sub = all.first(where: { $0.id == targetID }) else {
            return .result(dialog: "I couldn't find that subscription.")
        }
        let record = UsageRecord(subscription: sub, date: Date(), wasUsed: true, note: "via Siri")
        record.subscriptionID = sub.id   // keep the CloudKit backup link meaningful
        context.insert(record)
        sub.lastUsedDate = Date()
        try? context.save()
        return .result(dialog: "Got it — marked \(sub.name) as used today.")
    }
}

/// "What should I review this month in Drift?"
struct RunMonthlyReviewIntent: AppIntent {
    static var title: LocalizedStringResource = "Run monthly review"
    static var description = IntentDescription("Reviews your subscriptions for ones worth cancelling.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(SharedModelContainer.shared)
        let subs = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        let snapshots = subs.map { sub in
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
        let gateway = GatewayFactory.makeGateway()
        let review = try await gateway.generateMonthlyReview(for: snapshots)
        let count = review.suggestions.count
        let noun = count == 1 ? "subscription" : "subscriptions"
        return .result(dialog: "I found \(count) \(noun) worth reviewing this month.")
    }
}
