//
//  CategoryManagerView.swift
//  Drift
//
//  Lists every category and lets you manage the ones you created. Built-in
//  categories are shown but protected — only custom categories can be edited
//  or deleted. Deleting a category never deletes its subscriptions; they lose
//  their category and fall back to the neutral "no category" look. If a custom
//  category is in use, deleting it asks for confirmation first.
//

import SwiftData
import SwiftUI

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var editingCategory: Category?
    @State private var isCreating = false
    @State private var pendingDelete: Category?

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    row(for: category)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !isBuiltIn(category) {
                                Button(role: .destructive) {
                                    requestDelete(category)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
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
        .alert(
            "Delete category?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { category in
            Button("Delete", role: .destructive) { performDelete(category) }
            Button("Cancel", role: .cancel) {}
        } message: { category in
            Text(deleteMessage(for: category))
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

    private func inUseCount(_ category: Category) -> Int {
        category.subscriptions?.count ?? 0
    }

    private func deleteMessage(for category: Category) -> String {
        let count = inUseCount(category)
        let noun = count == 1 ? "subscription" : "subscriptions"
        return "\"\(category.name)\" is used by \(count) \(noun). They'll keep working but lose their category."
    }

    private func requestDelete(_ category: Category) {
        if inUseCount(category) == 0 {
            performDelete(category)
        } else {
            pendingDelete = category
        }
    }

    private func performDelete(_ category: Category) {
        // Reset any subscriptions using this category to the neutral look
        // before removing it, so no stale icon or color is left behind.
        for subscription in category.subscriptions ?? [] {
            subscription.iconName = "creditcard.fill"
            subscription.customColor = "#5E5CE6"
        }
        context.delete(category)
        try? context.save()
        pendingDelete = nil
    }
}
