//
//  CancelGuidesView.swift
//  Drift
//
//  Browse the bundled cancellation guides (50 services), searchable, each with
//  a friction badge. Tapping opens the step-by-step guide. The StalenessBanner
//  and "Worst offenders" segment arrive with the fuller Cancel screen; this is
//  the real list + detail driven by the existing CancellationGuideStore.
//

import Foundation
import SwiftUI

struct CancelGuidesView: View {
    @State private var store = CancellationGuideStore()

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                if let error = store.loadError {
                    ContentUnavailableView(
                        "Couldn't load guides",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                } else {
                    List(store.filteredAndSortedGuides) { guide in
                        NavigationLink(value: guide) {
                            CancelGuideRow(guide: guide)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Cancel")
            .searchable(text: $store.searchQuery, prompt: "Search services")
            .navigationDestination(for: CancellationGuide.self) { guide in
                CancellationGuideDetail(guide: guide)
            }
        }
        .task {
            // Match the list to the current App Store storefront (defaults to US).
            await store.refreshUserRegion()
        }
    }
}

private struct CancelGuideRow: View {
    let guide: CancellationGuide

    var body: some View {
        HStack(spacing: DriftSpacing.s12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(guide.serviceName)
                    .font(.body)
                    .lineLimit(1)
                Text(guide.category)
                    .font(.footnote)
                    .foregroundStyle(DriftTheme.subtleText)
                    .lineLimit(1)
            }

            Spacer(minLength: DriftSpacing.s8)

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
                    Link(destination: url) {
                        Label("Open cancellation page", systemImage: "arrow.up.right.square")
                    }
                }
            } else if guide.appleBilledOption {
                Section {
                    Label("Billed by Apple — cancel in Settings › Subscriptions",
                          systemImage: "apple.logo")
                        .font(.footnote)
                        .foregroundStyle(DriftTheme.subtleText)
                }
            }
        }
        .navigationTitle(guide.serviceName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
