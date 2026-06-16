//
//  SharedModelContainer.swift
//  Drift
//

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

    private static let appGroupID = "group.com.defrust.drift"
    private static let cloudKitContainerID = "iCloud.com.defrust.drift"

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: DriftSchemaV1.self)

        // Primary: App Group store + private CloudKit (production path).
        // `ModelConfiguration(groupContainer:)` TRAPS (it doesn't throw) when the
        // app isn't entitled to the group, so we must confirm the container is
        // reachable BEFORE building that configuration — otherwise the fallback
        // below can never run. The App Group / iCloud capabilities are added in
        // Week 2; until then this branch is skipped and we run on local storage.
        if isAppGroupAvailable, let container = try? makeCloudContainer(schema: schema) {
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

    /// Whether this build is actually entitled to the App Group. Returns `false`
    /// (never traps) when the capability hasn't been configured yet.
    private static var isAppGroupAvailable: Bool {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    private static func makeCloudContainer(schema: Schema) throws -> ModelContainer {
        let cloudConfig = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: DriftMigrationPlan.self,
            configurations: [cloudConfig]
        )
    }
}
