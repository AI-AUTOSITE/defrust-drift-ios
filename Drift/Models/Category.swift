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

extension Category {
    static let defaultPresets: [(name: String, color: String, symbol: String)] = [
        ("Streaming", "#FF453A", "play.tv.fill"),
        ("SaaS", "#5E5CE6", "briefcase.fill"),
        ("News", "#FF9F0A", "newspaper.fill"),
        ("Fitness", "#30D158", "figure.run"),
        ("AI", "#BF5AF2", "brain.head.profile"),
        ("Productivity", "#0A84FF", "checkmark.square.fill"),
        ("Music", "#FF2D92", "music.note"),
        ("Gaming", "#64D2FF", "gamecontroller.fill"),
        ("E-commerce", "#FFD60A", "cart.fill"),
        ("Other", "#8E8E93", "ellipsis.circle.fill")
    ]

    /// Seeds the ten default categories exactly once. Safe to call on every launch.
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<Self>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for (index, preset) in defaultPresets.enumerated() {
            let category = Self(
                name: preset.name,
                colorHex: preset.color,
                iconSymbol: preset.symbol,
                sortOrder: index
            )
            context.insert(category)
        }
        try? context.save()
    }
}
