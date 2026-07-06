//
//  CategoryManagerView.swift
//  Drift
//
//  Lists every category and lets you manage the ones you created. Built-in
//  categories are shown but protected — only custom categories can be edited
//  or deleted. Deleting a category never deletes its subscriptions; they just
//  lose their category (the model's delete rule nullifies the link).
//

import SwiftData
import SwiftUI

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var editingCategory: Category?
    @State private var isCreating = false

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    row(for: category)
                        .deleteDisabled(isBuiltIn(category))
                }
                .onDelete(perform: deleteCustom)
            } footer: {
                Text("Built-in categories can't be changed. Tap a custom category to edit it, or swipe to delete — its subscriptions stay and simply lose their category.")
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Label("New category", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorView(editing: category)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isCreating) {
            CategoryEditorView()
                .presentationDragIndicator(.visible)
        }
    }

    private func row(for category: Category) -> some View {
        let builtIn = isBuiltIn(category)
        return HStack(spacing: DriftSpacing.s12) {
            Image(systemName: category.iconSymbol)
                .foregroundStyle(Color.categoryTint(hex: category.colorHex))
                .frame(width: 28)

            Text(category.name)

            Spacer()

            if builtIn {
                Text("Built-in")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !builtIn {
                editingCategory = category
            }
        }
    }

    private func isBuiltIn(_ category: Category) -> Bool {
        Category.defaultPresetNames.contains(category.name)
    }

    private func deleteCustom(at offsets: IndexSet) {
        for index in offsets {
            let category = categories[index]
            if !isBuiltIn(category) {
                context.delete(category)
            }
        }
        try? context.save()
    }
}
