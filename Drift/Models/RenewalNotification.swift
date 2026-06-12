import Foundation
import SwiftData

extension DriftSchemaV1 {
    @Model
    final class RenewalNotification {
        var id: UUID = UUID()
        /// Backup identifier mirroring UsageRecord.subscriptionID.
        var subscriptionID: UUID = UUID()
        /// UI presets are 1, 3, and 7 days before renewal.
        var daysBeforeRenewal: Int = 3
        var isEnabled: Bool = true
        /// Guards against duplicate scheduling from BGAppRefreshTask (Part 1B).
        var lastScheduledFireDate: Date?

        // Inverse of Subscription.notifications
        var subscription: Subscription?

        init(
            subscription: Subscription? = nil,
            daysBeforeRenewal: Int = 3,
            isEnabled: Bool = true
        ) {
            self.id = UUID()
            self.subscriptionID = UUID()
            self.daysBeforeRenewal = daysBeforeRenewal
            self.isEnabled = isEnabled
            self.subscription = subscription
        }
    }
}
