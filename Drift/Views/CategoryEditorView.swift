//
//  CategoryEditorView.swift
//  Drift
//
//  A small sheet for creating a custom category: a name, an icon from a
//  curated SF Symbol grid, and a color. The result is a normal Category model,
//  so any subscription assigned to it inherits its icon and color exactly like
//  the built-in categories do.
//

import SwiftData
import SwiftUI

struct CategoryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    /// Called with the newly created category so the caller can select it.
    let onCreate: (Category) -> Void

    @State private var name = ""
    @State private var iconSymbol = "star.fill"
    @State private var colorHex = "#0A84FF"

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                }

                Section("Icon") {
                    iconGrid
                }

                Section("Color") {
                    colorGrid
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Self.gridColumns, spacing: DriftSpacing.s12) {
            ForEach(Self.iconChoices, id: \.self) { symbol in
                let isSelected = symbol == iconSymbol
                Button {
                    iconSymbol = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.categoryTint(hex: colorHex) : .primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: DriftRadius.m, style: .continuous)
                                .fill(isSelected ? Color.categoryTint(hex: colorHex).opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, DriftSpacing.s4)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Self.gridColumns, spacing: DriftSpacing.s12) {
            ForEach(Self.colorChoices, id: \.self) { hex in
                let isSelected = hex == colorHex
                Button {
                    colorHex = hex
                } label: {
                    Circle()
                        .fill(Color.categoryTint(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "Selected color" : "Color option")
            }
        }
        .padding(.vertical, DriftSpacing.s4)
    }

    private func save() {
        let nextOrder = (categories.map(\.sortOrder).max() ?? 0) + 1
        let category = Category(
            name: trimmedName,
            colorHex: colorHex,
            iconSymbol: iconSymbol,
            sortOrder: nextOrder
        )
        context.insert(category)
        try? context.save()
        onCreate(category)
        dismiss()
    }

    // MARK: - Curated choices

    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: DriftSpacing.s12),
        count: 6
    )

    private static let iconChoices: [String] = [
        "play.tv.fill", "film.fill", "music.note", "headphones",
        "gamecontroller.fill", "brain.head.profile", "sparkles", "newspaper.fill",
        "book.fill", "graduationcap.fill", "briefcase.fill", "checkmark.square.fill",
        "chart.bar.fill", "dollarsign.circle.fill", "creditcard.fill", "cart.fill",
        "bag.fill", "gift.fill", "figure.run", "heart.fill",
        "dumbbell.fill", "leaf.fill", "fork.knife", "cup.and.saucer.fill",
        "car.fill", "airplane", "house.fill", "bolt.fill",
        "wifi", "cloud.fill", "externaldrive.fill", "paintpalette.fill",
        "camera.fill", "pawprint.fill", "star.fill", "square.grid.2x2"
    ]

    private static let colorChoices: [String] = [
        "#FF453A", "#FF9500", "#FFD60A", "#30D158",
        "#64D2FF", "#0A84FF", "#5E5CE6", "#BF5AF2",
        "#FF2D92", "#FF375F", "#AC8E68", "#8E8E93"
    ]
}
