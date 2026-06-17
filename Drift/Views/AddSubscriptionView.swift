//
//  ServicePickerView.swift
//  Drift
//
//  A searchable picker over the 50 bundled services. Choosing one links the
//  subscription to a known service (its serviceID), which lets the detail
//  screen show the real cancellation guide and auto-fills name + category.
//  The friction badge is shown here too, so the trade-off is visible up front.
//

import Foundation
import SwiftUI

struct ServicePickerView: View {
    /// Called with the chosen guide, or `nil` for "Custom" (no linked service).
    let onSelect: (CancellationGuide?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = CancellationGuideStore()
    @State private var query = ""

    private var results: [CancellationGuide] {
        let sorted = store.allGuides.sorted {
            $0.serviceName.localizedCaseInsensitiveCompare($1.serviceName) == .orderedAscending
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter { $0.serviceName.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label("Custom (no linked service)", systemImage: "square.dashed")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    ForEach(results) { guide in
                        Button {
                            onSelect(guide)
                            dismiss()
                        } label: {
                            HStack(spacing: DriftSpacing.s12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(guide.serviceName)
                                        .font(.body)
                                    Text(guide.category)
                                        .font(.footnote)
                                        .foregroundStyle(DriftTheme.subtleText)
                                }
                                Spacer(minLength: DriftSpacing.s8)
                                DarkPatternBadge(score: guide.darkPatternScore)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Choose Service")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search services")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
