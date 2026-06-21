//
//  DriftWidgets.swift
//  DriftWidgetsExtension
//
//  Home Screen + Lock Screen widget for Drift. Reads the shared SwiftData store
//  through the App Group (group.com.defrust.drift) — read-only, with NO CloudKit
//  here. The main app owns the CloudKit mirroring; the widget just reads the
//  already-synced local store in the same App Group container.
//
//  Amounts are shown in USD: per the app's currency model the *comparison* total
//  is normalized to USD, while each subscription is billed in its own currency.
//  Tapping any size opens drift://overview (handled by RootView.onOpenURL).
//
//  Free for all users (spec §13.1): the widget is an acquisition channel for a
//  single one-time purchase, so every size is unlocked — no Pro gate here.
//
//  Swift 6 / main-actor note: SwiftData is read on @MainActor, matching the
//  app's AppIntents and notification handlers. The TimelineProvider methods stay
//  `nonisolated` (as the protocol requires) and hop to the main actor in a Task.
//  DriftEntry has explicit `nonisolated` initializers so the placeholder can be
//  built off the main actor.
//

import Charts
import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Read-only shared store (App Group, no CloudKit)

enum WidgetModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema(versionedSchema: DriftSchemaV1.self)
        let groupConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: false,
            groupContainer: .identifier("group.com.defrust.drift"),
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: groupConfig) {
            return container
        }
        // App Group somehow unavailable → in-memory so the widget renders the
        // placeholder instead of crashing the extension.
        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: memoryConfig) {
            return container
        }
        fatalError("DriftWidgets: could not create a ModelContainer")
    }()
}

// MARK: - Timeline entry

struct DriftEntry: TimelineEntry, Sendable {
    let date: Date
    let monthlyTotalUSD: Double
    let upcoming: [UpcomingItem]
    let categoryBreakdown: [CategoryAmount]

    nonisolated init(
        date: Date,
        monthlyTotalUSD: Double,
        upcoming: [UpcomingItem],
        categoryBreakdown: [CategoryAmount]
    ) {
        self.date = date
        self.monthlyTotalUSD = monthlyTotalUSD
        self.upcoming = upcoming
        self.categoryBreakdown = categoryBreakdown
    }

    struct UpcomingItem: Identifiable, Hashable, Sendable {
        let id: UUID
        let name: String
        let date: Date
        let amountUSD: Double

        nonisolated init(id: UUID, name: String, date: Date, amountUSD: Double) {
            self.id = id
            self.name = name
            self.date = date
            self.amountUSD = amountUSD
        }
    }

    struct CategoryAmount: Hashable, Sendable {
        let category: String
        let colorHex: String
        let amountUSD: Double

        nonisolated init(category: String, colorHex: String, amountUSD: Double) {
            self.category = category
            self.colorHex = colorHex
            self.amountUSD = amountUSD
        }
    }

    /// Sample data for the widget gallery and the placeholder while loading.
    nonisolated static let preview = DriftEntry(
        date: .now,
        monthlyTotalUSD: 42.99,
        upcoming: [
            UpcomingItem(id: UUID(), name: "Netflix", date: .now.addingTimeInterval(86_400 * 2), amountUSD: 15.49),
            UpcomingItem(id: UUID(), name: "Spotify", date: .now.addingTimeInterval(86_400 * 5), amountUSD: 10.99),
            UpcomingItem(id: UUID(), name: "iCloud+", date: .now.addingTimeInterval(86_400 * 9), amountUSD: 2.99)
        ],
        categoryBreakdown: [
            CategoryAmount(category: "Streaming", colorHex: "#FF453A", amountUSD: 28.0),
            CategoryAmount(category: "Productivity", colorHex: "#0A84FF", amountUSD: 14.99)
        ]
    )
}

// MARK: - Timeline provider

struct DriftTimelineProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> DriftEntry {
        .preview
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping (DriftEntry) -> Void) {
        Task { @MainActor in
            completion(Self.currentEntry())
        }
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping (Timeline<DriftEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.currentEntry()
            let now = Date()
            // Refresh at the next renewal, but at least once a day.
            let nextRenewal = entry.upcoming.first?.date ?? now.addingTimeInterval(24 * 3600)
            let reloadAt = min(nextRenewal, now.addingTimeInterval(24 * 3600))
            completion(Timeline(entries: [entry], policy: .after(reloadAt)))
        }
    }

    @MainActor
    private static func currentEntry() -> DriftEntry {
        let context = ModelContext(WidgetModelContainer.shared)
        let all = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        let active = all.filter { !$0.isPaused }
        let now = Date()

        let monthlyUSD = active.reduce(0.0) { running, sub in
            running + ExchangeRates.toUSD(sub.monthlyCost, code: sub.currencyCode)
        }

        let upcoming = active
            .filter { $0.nextRenewalDate > now }
            .sorted { $0.nextRenewalDate < $1.nextRenewalDate }
            .prefix(5)
            .map { sub in
                DriftEntry.UpcomingItem(
                    id: sub.id,
                    name: sub.name,
                    date: sub.nextRenewalDate,
                    amountUSD: ExchangeRates.toUSD(sub.monthlyCost, code: sub.currencyCode)
                )
            }

        let breakdown = Dictionary(grouping: active) { $0.category?.name ?? "Other" }
            .map { name, subs in
                DriftEntry.CategoryAmount(
                    category: name,
                    colorHex: subs.first?.category?.colorHex ?? "#8E8E93",
                    amountUSD: subs.reduce(0.0) { $0 + ExchangeRates.toUSD($1.monthlyCost, code: $1.currencyCode) }
                )
            }
            .sorted { $0.amountUSD > $1.amountUSD }

        return DriftEntry(
            date: now,
            monthlyTotalUSD: monthlyUSD,
            upcoming: Array(upcoming),
            categoryBreakdown: breakdown
        )
    }
}

// MARK: - Entry view (routes by widget family)

struct DriftWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: DriftEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        case .systemLarge: LargeWidgetView(entry: entry)
        case .accessoryInline: InlineWidgetView(entry: entry)
        case .accessoryRectangular: RectangularWidgetView(entry: entry)
        case .accessoryCircular: CircularWidgetView(entry: entry)
        default: SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget configuration

struct DriftSummaryWidget: Widget {
    let kind = "com.defrust.drift.widget.summary"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DriftTimelineProvider()) { entry in
            DriftWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Drift")
        .description("See your monthly total and upcoming renewals.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryInline, .accessoryRectangular, .accessoryCircular
        ])
    }
}

// MARK: - Home Screen views

private struct SmallWidgetView: View {
    let entry: DriftEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Monthly")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.monthlyTotalUSD, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer()
            if let next = entry.upcoming.first {
                Text("\(next.name) in \(daysUntil(next.date))d")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No upcoming renewals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "drift://overview"))
    }
}

private struct MediumWidgetView: View {
    let entry: DriftEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next renewals")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.upcoming.isEmpty {
                Spacer()
                Text("No upcoming renewals")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.upcoming.prefix(3)) { item in
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(item.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.amountUSD, format: .currency(code: "USD"))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "drift://overview"))
    }
}

private struct LargeWidgetView: View {
    let entry: DriftEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.monthlyTotalUSD, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.title3.bold())
                Spacer()
                Text("\(entry.upcoming.count) upcoming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.categoryBreakdown.isEmpty {
                Chart(entry.categoryBreakdown, id: \.category) { row in
                    SectorMark(
                        angle: .value("USD", row.amountUSD),
                        innerRadius: .ratio(0.6),
                        angularInset: 1
                    )
                    .foregroundStyle(Color(hex: row.colorHex))
                }
                .frame(height: 104)
                .chartLegend(.hidden)
            }
            ForEach(entry.upcoming.prefix(5)) { item in
                HStack {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(item.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "drift://overview"))
    }
}

// MARK: - Lock Screen (accessory) views

private struct InlineWidgetView: View {
    let entry: DriftEntry

    var body: some View {
        Group {
            if let next = entry.upcoming.first {
                Text("\(next.name) in \(daysUntil(next.date))d")
            } else {
                Text("No renewals due")
            }
        }
        .containerBackground(.clear, for: .widget)   // ← 追加
    }
}

private struct RectangularWidgetView: View {
    let entry: DriftEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.monthlyTotalUSD, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.headline)
            if let next = entry.upcoming.first {
                Text("\(next.name) in \(daysUntil(next.date))d")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("\(entry.upcoming.count) upcoming")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "drift://overview"))
    }
}

private struct CircularWidgetView: View {
    let entry: DriftEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text("\(entry.upcoming.count)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("due")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "drift://overview"))
    }
}

// MARK: - Helpers

/// Whole days from now until `date`, clamped at 0 so a renewal that is
/// technically a few hours past midnight never shows as a negative count.
private func daysUntil(_ date: Date) -> Int {
    max(0, Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0)
}
