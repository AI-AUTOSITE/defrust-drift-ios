//
//  CategoryPickerView.swift
//  Drift
//
//  A simple selection list for a subscription's category. Unlike the system
//  Picker menu (which renders every icon in one tint), this shows each
//  category in its own real color. Tapping a row selects it and closes.
//

import SwiftData
import SwiftUI

struct CategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @Binding var selection: PersistentIdentifier?

    var body: some View {
        NavigationStack {
            List {
                Button {
                    choose(nil)
                } label: {
                    row(icon: "circle", color: nil, name: "None", isSelected: selection == nil)
                }
                .buttonStyle(.plain)

                ForEach(categories) { category in
                    Button {
                        choose(category.persistentModelID)
                    } label: {
                        row(
                            icon: category.iconSymbol,
                            color: Color.categoryTint(hex: category.colorHex),
                            name: category.name,
                            isSelected: selection == category.persistentModelID
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(icon: String, color: Color?, name: String, isSelected: Bool) -> some View {
        HStack(spacing: DriftSpacing.s12) {
            Image(systemName: icon)
                .foregroundStyle(color ?? Color.secondary)
                .frame(width: 28)

            Text(name)
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DriftTheme.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private func choose(_ id: PersistentIdentifier?) {
        selection = id
        dismiss()
    }
}
