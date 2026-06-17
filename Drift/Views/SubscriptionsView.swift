//
//  SubscriptionsView.swift
//  Drift
//
//  Lists the user's subscriptions and is the place to add, open and remove
//  them. Tapping a row pushes the detail screen (edit lives there now).
//  Deletion follows the anti-dark-pattern rule (Part 2 §10.2): no scary
//  confirmation dialog — the row disappears immediately and a brief Undo banner
//  lets the user take it back. The delete is only committed once that window
//  passes.
//

import SwiftData
import SwiftUI

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subscription.name)
    private var subscriptions: [Subscription]

    @State private var isAdding = false
    @State private var pendingDelete: Subscription?
    @State private var deleteTick = 0

    /// Hides the row that is in its Undo window so it reads as removed at once.
    private var visibleSubscriptions: [Subscription] {
        guard let pendingDelete else { return subscriptions }
        return subscriptions.filter { $0.persistentModelID != pendingDelete.persistentModelID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleSubscriptions.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions",
                        systemImage: "creditcard",
                        description: Text("Tap + to add your first subscription.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Subscriptions")
            .navigationDestination(for: Subscription.self) { subscription in
                SubscriptionDetailView(subscription: subscription) { target in
                    requestDelete(target)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add Subscription", systemImage: "plus")
                    }
                }
            }
            .overlay(alignment: .bottom) { undoBanner }
        }
        .sheet(isPresented: $isAdding) {
            AddSubscriptionView()
        }
        .driftHaptic(.subscriptionDeleted, trigger: deleteTick)
        .task(id: pendingDelete?.persistentModelID) {
            // Commit the delete once the Undo window elapses (unless undone,
            // which cancels and restarts this task with a nil id).
            guard pendingDelete != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            commitPendingDelete()
        }
    }

    private var list: some View {
        List {
            ForEach(visibleSubscriptions, id: \.persistentModelID) { subscription in
                NavigationLink(value: subscription) {
                    SubscriptionRow(subscription: subscription)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        requestDelete(subscription)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let pendingDelete {
            HStack(spacing: DriftSpacing.s12) {
                Text("Removed \(pendingDelete.name)")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: DriftSpacing.s8)
                Button("Undo") { undoDelete() }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, DriftSpacing.s16)
            .padding(.vertical, DriftSpacing.s12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, DriftSpacing.s16)
            .padding(.bottom, DriftSpacing.s8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func requestDelete(_ subscription: Subscription) {
        // Finalize any previous pending delete before starting a new one.
        commitPendingDelete()
        deleteTick += 1
        withAnimation { pendingDelete = subscription }
    }

    private func undoDelete() {
        withAnimation { pendingDelete = nil }
    }

    private func commitPendingDelete() {
        guard let target = pendingDelete else { return }
        context.delete(target)
        try? context.save()
        pendingDelete = nil
    }
}

private struct SubscriptionRow: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: DriftSpacing.s12) {
            Image(systemName: subscription.iconName)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(hex: subscription.customColor))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.body)
                Text("Renews \(subscription.nextRenewalDate.formatted(.dateTime.month().day()))")
                    .font(.footnote)
                    .foregroundStyle(DriftTheme.subtleText)
            }

            Spacer(minLength: DriftSpacing.s8)

            Text(subscription.monthlyCost,
                 format: .currency(code: subscription.currencyCode))
                .font(DriftTypography.amount)
        }
        .padding(.vertical, DriftSpacing.s4)
    }
}
