import Foundation
import SwiftData

/// Versioned from day one so future schema changes can migrate safely.
/// Shipping v1 unversioned and adding VersionedSchema later crashes with
/// "Cannot use staged migration with an unknown model version" (Part 1A §2.1).
enum DriftSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Subscription.self,
            UsageRecord.self,
            Category.self,
            RenewalNotification.self
        ]
    }
}

// MARK: - Typealiases for clean call sites
// Views and view models say `Subscription`, not `DriftSchemaV1.Subscription`.
// When V2 ships, only these typealiases move to the new schema.

typealias Subscription = DriftSchemaV1.Subscription
typealias UsageRecord = DriftSchemaV1.UsageRecord
typealias Category = DriftSchemaV1.Category
typealias RenewalNotification = DriftSchemaV1.RenewalNotification
