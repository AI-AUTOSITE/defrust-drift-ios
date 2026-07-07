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
        /// Where this subscription is billed (App Store, Google Play, Amazon, …),
        /// which decides where cancellation sends the user. Stored as a raw String
        /// like `billingCycleRaw` so new channels need no migration; `nil` means
        /// not set yet (treated as "ask where you subscribed"). See `BillingChannel`.
        var billingChannelRaw: String?
        var iconName: String = "creditcard.fill" // SF Symbol name
        var customColor: String = "#5E5CE6" // hex string (systemIndigo)

        // MARK: - Cost
        /// Normalized monthly cost. Yearly input is stored /12, weekly ×4
        /// (4-weeks-per-month convention — see bug #22). The per-cycle ⇄ monthly
        /// conversion lives in `BillingCycle.monthlyCost(forCycleAmount:)` /
        /// `cycleAmount(forMonthlyCost:)`, so totals are a plain sum.
        var monthlyCost: Decimal = 0
        var currencyCode: String = "USD" // ISO 4217
        var billingCycleRaw: String = BillingCycle.monthly.rawValue
        /// Only meaningful while billingCycle == .custom.
        var customCycleDays: Int?

        // MARK: - Dates
        var startDate: Date = Date()
        var nextRenewalDate: Date = Date()
        /// User-chosen one-time "remind me to cancel this" date/time. `nil` means
        /// no reminder. Scheduled as a `cancel-<uuid>` local notification, separate
        /// from the automatic renewal reminders. Optional so CloudKit can add the
        /// field without a heavyweight migration.
        var cancelReminderDate: Date?

        // MARK: - State
        var isPaused: Bool = false
        var pausedUntil: Date?
        /// When the subscription was paused (set by `applyPause`). `nil` when
        /// active, or for subscriptions paused before this field existed.
        /// Optional so CloudKit can add it without a heavyweight migration.
        var pausedDate: Date?
        var lastUsedDate: Date?
        /// "daily" / "weekly" / "monthly" / "rarely" / "never"
        var frequencyTag: String?

        /// Whether the subscription has been canceled. Canceled subscriptions
        /// leave the active totals and notifications, and feed cumulative savings.
        var isCanceled: Bool = false
        /// When the subscription was canceled (set by `applyCancel`). `nil` when
        /// active. Optional so CloudKit can add it without a heavyweight migration.
        var canceledDate: Date?

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

        /// Where the user pays for this subscription. `nil` when unset. Stored as
        /// a raw String so adding future channels needs no migration (mirrors
        /// `billingCycle`). Drives cancellation routing — see `CancellationRouter`.
        var billingChannel: BillingChannel? {
            get { billingChannelRaw.flatMap(BillingChannel.init(rawValue:)) }
            set { billingChannelRaw = newValue?.rawValue }
        }

        /// Non-optional access for call sites (relationships must stay optional for CloudKit).
        var unwrappedUsageRecords: [UsageRecord] {
            usageRecords ?? []
        }

        var unwrappedNotifications: [RenewalNotification] {
            notifications ?? []
        }

        // MARK: - Mutations
        /// Pause or resume the subscription, keeping the three pause fields
        /// consistent: pausing stamps `pausedDate` with now; resuming clears both
        /// `pausedDate` and any scheduled `pausedUntil`. Call this from every
        /// pause entry point so no field is left stale.
        func applyPause(_ paused: Bool) {
            isPaused = paused
            if paused {
                pausedDate = Date()
            } else {
                pausedDate = nil
                pausedUntil = nil
            }
        }

        /// Cancel or reactivate the subscription. Canceling stamps `canceledDate`
        /// and supersedes any pause; reactivating clears `canceledDate`.
        func applyCancel(_ canceled: Bool) {
            isCanceled = canceled
            canceledDate = canceled ? Date() : nil
            if canceled {
                isPaused = false
                pausedDate = nil
                pausedUntil = nil
            }
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
