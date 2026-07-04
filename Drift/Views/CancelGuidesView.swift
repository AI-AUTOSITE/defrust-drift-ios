//
//  CancelGuidesView.swift
//  Drift
//
//  The Cancel tab. Two ways in:
//   • "Cancel by where you pay" → the billing-channel guides (Apple, Google,
//     Amazon, Roku, PayPal, carrier, direct…), because where you cancel depends
//     on how you pay, not just which service it is.
//   • Browse the bundled service guides (50), searchable, each with a friction
//     badge, sortable alphabetically or hardest-to-cancel-first.
//  A quiet staleness banner appears when a visible guide is past its
//  re-verification window, so we never imply steps are fresher than they are.
//
//  All of this wires up capability that already lived on CancellationGuideStore
//  (`isStale`, `sortMode.darkPatternDescending`) plus the BillingChannel guides.
//

import Foundation
import SwiftUI

struct CancelGuidesView: View {
    @State private var store = CancellationGuideStore()

    private var searchIsActive: Bool {
        !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when at least one guide the user can see is past its re-verification
    /// window. Drives the (deliberately quiet) staleness banner.
    private var hasStaleGuides: Bool {
        store.regionFilteredGuides.contains { store.isStale($0) }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            content
                .navigationTitle("Cancel")
                .searchable(text: $store.searchQuery, prompt: "Search services")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenu
                    }
                }
                .navigationDestination(for: CancellationGuide.self) { guide in
                    CancellationGuideDetail(guide: guide)
                }
        }
        .task {
            // Match the list to the current App Store storefront (defaults to US).
            await store.refreshUserRegion()
        }
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if let error = store.loadError {
            ContentUnavailableView(
                "Couldn't load guides",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        } else {
            guidesList
        }
    }

    private var guidesList: some View {
        List {
            // Honest heads-up, only when there's actually something stale to warn
            // about and the user isn't mid-search.
            if hasStaleGuides && !searchIsActive {
                Section {
                    StalenessBanner()
                }
            }

            // Route in by billing channel — the primary way to cancel correctly.
            if !searchIsActive {
                Section {
                    NavigationLink {
                        BillingChannelListView()
                    } label: {
                        Label("Cancel by where you pay", systemImage: "creditcard")
                    }
                } footer: {
                    Text("Where you cancel depends on how you pay, not only which service it is. If you subscribed through a platform like Apple or Amazon, you usually cancel there.")
                }
            }

            // Browse the bundled service guides.
            Section {
                ForEach(store.filteredAndSortedGuides) { guide in
                    NavigationLink(value: guide) {
                        CancelGuideRow(guide: guide)
                    }
                }
            } header: {
                Text(servicesHeader)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if searchIsActive && store.filteredAndSortedGuides.isEmpty {
                ContentUnavailableView.search(text: store.searchQuery)
            }
        }
    }

    // MARK: - Sort

    /// Section header reflects the current sort so the mode is always visible.
    private var servicesHeader: String {
        isSort(.darkPatternDescending) ? "Hardest to cancel first" : "All services"
    }

    /// Sort control. Plain `Button`s (not a `Picker`) so we set `store.sortMode`
    /// directly and draw our own checkmarks.
    private var sortMenu: some View {
        Menu {
            Button {
                store.sortMode = .alphabetical
            } label: {
                if isSort(.alphabetical) {
                    Label("Alphabetical", systemImage: "checkmark")
                } else {
                    Text("Alphabetical")
                }
            }
            Button {
                store.sortMode = .darkPatternDescending
            } label: {
                if isSort(.darkPatternDescending) {
                    Label("Hardest to cancel first", systemImage: "checkmark")
                } else {
                    Text("Hardest to cancel first")
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private func isSort(_ mode: CancellationGuideStore.SortMode) -> Bool {
        switch (store.sortMode, mode) {
        case (.alphabetical, .alphabetical),
             (.darkPatternDescending, .darkPatternDescending):
            return true
        default:
            return false
        }
    }
}

// MARK: - Staleness banner

/// A quiet, honest note that some guides may be out of date. Only shown when a
/// visible guide is past its re-verification window (see `store.isStale`), so it
/// stays invisible until it has something true to say.
private struct StalenessBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: DriftSpacing.s12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(DriftTheme.warningSoft)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DriftSpacing.s2) {
                Text("Some steps may have changed")
                    .font(.subheadline.weight(.semibold))
                Text("A few of these guides were last checked a while ago. Services change how they cancel, so double-check on the service's own page.")
                    .font(.footnote)
                    .foregroundStyle(DriftTheme.subtleText)
            }
        }
        .padding(.vertical, DriftSpacing.s4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Billing channel list ("where you pay")

/// Lists every billing channel the user might pay through and opens that
/// channel's cancellation guide. Pushed onto the Cancel tab's existing
/// navigation stack, so it has no `NavigationStack` of its own.
private struct BillingChannelListView: View {
    var body: some View {
        List(BillingChannel.selectableChannels) { channel in
            NavigationLink {
                BillingChannelGuideView(channel: channel, serviceName: "")
            } label: {
                VStack(alignment: .leading, spacing: DriftSpacing.s2) {
                    Text(channel.displayName)
                        .font(.body)
                    if let hint = channel.statementHint {
                        Text("On your statement: \(hint)")
                            .font(.footnote)
                            .foregroundStyle(DriftTheme.subtleText)
                    }
                }
                .padding(.vertical, DriftSpacing.s4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Where you pay")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Rows & detail (unchanged)

private struct CancelGuideRow: View {
    let guide: CancellationGuide
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Larger text makes the friction badge wide enough to crush the service
        // name down to "Am…". So once the text is enlarged the row switches from
        // a single line to a vertical stack: the name keeps the full width on its
        // own line(s) and the badge drops beneath it. At normal sizes it stays a
        // tidy one-liner. Same child views either way, so AnyLayout just swaps
        // the arrangement.
        let isLarge = dynamicTypeSize >= .xLarge
        let layout = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DriftSpacing.s8))
            : AnyLayout(HStackLayout(spacing: DriftSpacing.s12))

        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(guide.serviceName)
                    .font(.body)
                    .lineLimit(isLarge ? 2 : 1)
                Text(guide.category)
                    .font(.footnote)
                    .foregroundStyle(DriftTheme.subtleText)
                    .lineLimit(isLarge ? 2 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DarkPatternBadge(score: guide.darkPatternScore)
        }
        .padding(.vertical, DriftSpacing.s4)
    }
}

/// Step-by-step guide screen. Internal (not private) so the subscription
/// detail screen can reuse it when a subscription matches a known service.
struct CancellationGuideDetail: View {
    let guide: CancellationGuide

    var body: some View {
        List {
            Section {
                HStack {
                    DarkPatternBadge(score: guide.darkPatternScore)
                    Spacer()
                    Label("\(guide.estimatedTimeMinutes) min", systemImage: "clock")
                        .font(.footnote)
                        .foregroundStyle(DriftTheme.subtleText)
                }
                if let warning = guide.warningNote {
                    Label(warning, systemImage: "exclamationmark.bubble")
                        .font(.footnote)
                }
            }

            Section("Steps") {
                ForEach(guide.steps, id: \.order) { step in
                    VStack(alignment: .leading, spacing: DriftSpacing.s4) {
                        Text("\(step.order). \(step.action)")
                            .font(.body)
                        if let note = step.supportingNote {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(DriftTheme.subtleText)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let urlString = guide.primaryCancelURL, let url = URL(string: urlString) {
                Section {
                    ExternalLinkButton(url: url) {
                        Label("Open cancellation page", systemImage: "arrow.up.right.square")
                    }
                }
            } else if guide.appleBilledOption, let appleURL = BillingChannel.appleAppStore.managementURL {
                Section {
                    ExternalLinkButton(url: appleURL) {
                        Label("Open Subscriptions to cancel", systemImage: "apple.logo")
                    }
                } footer: {
                    Text("Opens Subscriptions in the App Store — find \(guide.serviceName) to cancel.")
                }
            }

            Section {
                Text("Steps last verified \(guide.lastVerifiedDate).")
                    .font(.caption)
                    .foregroundStyle(DriftTheme.subtleText)
            }
        }
        .navigationTitle(guide.serviceName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
