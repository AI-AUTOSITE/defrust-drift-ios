import Foundation
import SwiftData

/// The single SwiftData container shared by the app, the widget extension, and
/// AppIntents. All three open the SAME store via the App Group and sync through the
/// private CloudKit database. Built lazily on first access.
///
/// IMPORTANT: add this file's Target Membership to BOTH the app and the widget
/// extension (once that target exists). Built the same way as `DriftSchemaV1Tests`'
/// in-memory container — versioned schema + migration plan — but on the real store.
enum SharedModelContainer {
    static let shared: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: DriftSchemaV1.self)

        // Primary: App Group store + private CloudKit (production path).
        let cloudConfig = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier("group.com.defrust.drift"),
            cloudKitDatabase: .private("iCloud.com.defrust.drift")
        )
        if let container = try? ModelContainer(
            for: schema,
            migrationPlan: DriftMigrationPlan.self,
            configurations: [cloudConfig]
        ) {
            return container
        }

        // Fallback: local on-disk store — e.g. before the App Group / CloudKit
        // entitlements are configured in a dev build. Keeps the app launchable.
        let localConfig = ModelConfiguration(schema: schema)
        if let container = try? ModelContainer(
            for: schema,
            migrationPlan: DriftMigrationPlan.self,
            configurations: [localConfig]
        ) {
            return container
        }

        // Last resort: in-memory, so an extension or preview can still boot.
        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: [memoryConfig]) {
            return container
        }

        fatalError("Drift could not create any ModelContainer for DriftSchemaV1.")
    }
}
