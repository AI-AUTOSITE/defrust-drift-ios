import Foundation
import SwiftData

extension DriftSchemaV1 {
    @Model
    final class Subscription {
        // MARK: - Identity & Display
        /// Stable per-record identifier. Used for notification request IDs
        /// (`renewal-<uuid>-<daysBefore>`), the AppIntents `SubscriptionEntity`,
        /// and `drift://subscription/<uuid>` deep links. Not `.unique` — CloudKit
        /// does not support unique constraints — matching the other models.
        var id: UUID = UUID()
        var name: String = ""
        /// Joins to a CancellationGuide entry (Part 1C), e.g. "netflix".
        /// The special value "apple-subscription" routes to showManageSubscriptions(in:).
        var serviceID: String?
        var iconName: String = "creditcard.fill" // SF Symbol name
        var customColor: String = "#5E5CE6" // hex string (systemIndigo)

        // MARK: - Cost
        /// Normalized monthly cost. Yearly input is stored /12, weekly *4.345
        /// (conversion logic lives in the view model), so totals are a plain sum.
        var monthlyCost: Decimal = 0
        var currencyCode: String = "USD" // ISO 4217
        var billingCycleRaw: String = BillingCycle.monthly.rawValue
        /// Only meaningful while billingCycle == .custom.
        var customCycleDays: Int?

        // MARK: - Dates
        var startDate: Date = Date()
        var nextRenewalDate: Date = Date()

        // MARK: - State
        var isPaused: Bool = false
        var pausedUntil: Date?
        var lastUsedDate: Date?
        /// "daily" / "weekly" / "monthly" / "rarely" / "never"
        var frequencyTag: String?

        // MARK: - Categorization
        var category: Category?
        var notes: String = ""

        // MARK: - Relationships
        @Relationship(deleteRule: .cascade, inverse: \UsageRecord.subscription)
        var usageRecords: [UsageRecord]? = []

        @Relationship(deleteRule: .cascade, inverse: \RenewalNotification.subscription)
        var notifications: [RenewalNotification]? = []

        // MARK: - Computed
        /// Stored as a raw String so adding future enum cases needs no migration.
        var billingCycle: BillingCycle {
            get { BillingCycle(rawValue: billingCycleRaw) ?? .monthly }
            set { billingCycleRaw = newValue.rawValue }
        }

        /// Non-optional access for call sites (relationships must stay optional for CloudKit).
        var unwrappedUsageRecords: [UsageRecord] {
            usageRecords ?? []
        }

        var unwrappedNotifications: [RenewalNotification] {
            notifications ?? []
        }

        // MARK: - Init
        init(
            name: String = "",
            monthlyCost: Decimal = 0,
            currencyCode: String = "USD",
            billingCycle: BillingCycle = .monthly,
            startDate: Date = Date(),
            nextRenewalDate: Date = Date(),
            iconName: String = "creditcard.fill",
            customColor: String = "#5E5CE6"
        ) {
            self.id = UUID()
            self.name = name
            self.monthlyCost = monthlyCost
            self.currencyCode = currencyCode
            self.billingCycleRaw = billingCycle.rawValue
            self.startDate = startDate
            self.nextRenewalDate = nextRenewalDate
            self.iconName = iconName
            self.customColor = customColor
        }
    }
}
