import Foundation
import SwiftData

extension DriftSchemaV1 {
    @Model
    final class Category {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String = "#5E5CE6"
        var iconSymbol: String = "square.grid.2x2"
        /// CloudKit does not support ordered relationships,
        /// so display order is managed explicitly.
        var sortOrder: Int = 0

        // Category deletion keeps subscriptions and just clears their category.
        @Relationship(deleteRule: .nullify, inverse: \Subscription.category)
        var subscriptions: [Subscription]? = []

        init(
            name: String = "",
            colorHex: String = "#5E5CE6",
            iconSymbol: String = "square.grid.2x2",
            sortOrder: Int = 0
        ) {
            self.id = UUID()
            self.name = name
            self.colorHex = colorHex
            self.iconSymbol = iconSymbol
            self.sortOrder = sortOrder
        }
    }
}

// MARK: - Default categories (seeded on first launch)

/// Lightweight seeding value. A struct instead of a tuple keeps
/// SwiftLint's large_tuple rule satisfied (tuples max out at 2 members).
private struct CategoryPreset: Sendable {
    let name: String
    let color: String
    let symbol: String

    init(_ name: String, _ color: String, _ symbol: String) {
        self.name = name
        self.color = color
        self.symbol = symbol
    }
}

extension Category {
    private static let defaultPresets: [CategoryPreset] = [
        CategoryPreset("Streaming", "#FF453A", "play.tv.fill"),
        CategoryPreset("SaaS", "#5E5CE6", "briefcase.fill"),
        CategoryPreset("News", "#FF9F0A", "newspaper.fill"),
        CategoryPreset("Fitness", "#30D158", "figure.run"),
        CategoryPreset("AI", "#BF5AF2", "brain.head.profile"),
        CategoryPreset("Productivity", "#0A84FF", "checkmark.square.fill"),
        CategoryPreset("Music", "#FF2D92", "music.note"),
        CategoryPreset("Gaming", "#64D2FF", "gamecontroller.fill"),
        CategoryPreset("E-commerce", "#FFD60A", "cart.fill"),
        CategoryPreset("Design", "#FF375F", "paintpalette.fill"),
        CategoryPreset("Education", "#AC8E68", "graduationcap.fill"),
        CategoryPreset("Health", "#FF6961", "heart.fill"),
        CategoryPreset("Finance", "#32ADE6", "dollarsign.circle.fill"),
        CategoryPreset("Storage", "#5AC8FA", "externaldrive.fill"),
        CategoryPreset("Food & Drink", "#FF9500", "fork.knife"),
        CategoryPreset("Transport", "#40C8E0", "car.fill"),
        CategoryPreset("Other", "#8E8E93", "ellipsis.circle.fill")
    ]

    /// The number of built-in categories seeded on first launch. Exposed so
    /// tests track the preset list automatically instead of hard-coding a count.
    static var defaultPresetCount: Int { defaultPresets.count }

    /// Ensures exactly one of each default category exists. Safe to call on
    /// every launch.
    ///
    /// With CloudKit enabled, a fresh local store can seed its ten categories
    /// before iCloud syncs its own copy down — and CloudKit allows no unique
    /// constraints — so the same category can end up stored more than once.
    /// We therefore first merge duplicates by name (keeping one and moving its
    /// subscriptions onto it), then add any preset that is still missing.
    /// Duplicates created by an earlier launch are collapsed the next time
    /// this runs.
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Self>())) ?? []

        var keepers: [String: Self] = [:]
        var didChange = false

        // Merge duplicates: keep the lowest sortOrder, move subscriptions over.
        for category in all.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if let keeper = keepers[category.name] {
                for subscription in category.subscriptions ?? [] {
                    subscription.category = keeper
                }
                context.delete(category)
                didChange = true
            } else {
                keepers[category.name] = category
            }
        }

        // Seed any preset that is still missing (idempotent by name).
        for (index, preset) in defaultPresets.enumerated() where keepers[preset.name] == nil {
            let category = Self(
                name: preset.name,
                colorHex: preset.color,
                iconSymbol: preset.symbol,
                sortOrder: index
            )
            context.insert(category)
            keepers[preset.name] = category
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
