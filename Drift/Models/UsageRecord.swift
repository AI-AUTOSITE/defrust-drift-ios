import Foundation
import SwiftData

extension DriftSchemaV1 {
    @Model
    final class UsageRecord {
        var id: UUID = UUID()
        /// Backup identifier in case the relationship is temporarily unresolved
        /// during CloudKit sync ("partial data" scenarios).
        var subscriptionID: UUID = UUID()
        var date: Date = Date()
        var wasUsed: Bool = true
        var note: String?

        // Inverse of Subscription.usageRecords
        var subscription: Subscription?

        init(
            subscription: Subscription? = nil,
            date: Date = Date(),
            wasUsed: Bool = true,
            note: String? = nil
        ) {
            self.id = UUID()
            self.subscriptionID = UUID()
            self.date = date
            self.wasUsed = wasUsed
            self.note = note
            self.subscription = subscription
        }
    }
}
