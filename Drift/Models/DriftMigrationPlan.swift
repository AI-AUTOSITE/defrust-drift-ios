import Foundation
import SwiftData

/// Passed to ModelContainer from day one so v1 ships already versioned.
/// V1-only for now — schemas and stages grow together with DriftSchemaV2
/// (households / CKShare, see Part 1A §2.8).
enum DriftMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            DriftSchemaV1.self
            // DriftSchemaV2.self — added when households ship
        ]
    }

    static var stages: [MigrationStage] {
        [
            // .custom(fromVersion: DriftSchemaV1.self, toVersion: DriftSchemaV2.self, ...)
        ]
    }
}
