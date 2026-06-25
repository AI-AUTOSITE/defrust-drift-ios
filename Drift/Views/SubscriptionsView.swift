//
//  SubscriptionsView.swift
//  Drift
//
//  Lists the user's subscriptions and is the place to add, open and remove
//  them. Tapping a row pushes the detail screen (edit lives there now).
//  Deletion follows the anti-dark-pattern rule (Part 2 §10.2): no scary
//  confirmation dialog — the row disappears immediately and a brief Undo banner
//  lets the user take it back. The delete is only committed once that window
//  passes. Adding is gated by the free tier: at the limit, the "+" opens the
//  paywall instead of an empty form.
//

import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(DeletionState.self) private var deletionState
    @Environment(DriftStore.self) private var store
    @Query(sort: \Subscription.name)
    private var subscriptions: [Subscription]

    @State private var isAdding = false
    @State private var isShowingPaywall = false
    @State private var pendingDelete: Subscription?
    @State private var deleteTick = 0
    @State private var pauseTick = 0
    @State private var undoTick = 0

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
                        requestAdd()
                    } label: {
                        Label("Add Subscription", systemImage: "plus")
                    }
                }
            }
            .overlay(alignment: .bottom) { undoBanner }
        }
        .sheet(isPresented: $isAdding) {
            AddSubscriptionView()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
                .presentationDragIndicator(.visible)
        }
        .driftHaptic(.subscriptionDeleted, trigger: deleteTick)
        .driftHaptic(.subscriptionPaused, trigger: pauseTick)
        .driftHaptic(.navigationLight, trigger: undoTick)
        .task(id: pendingDelete?.persistentModelID) {
            // Commit the delete once the Undo window elapses (unless undone,
            // which cancels and restarts this task with a nil id). VoiceOver and
            // Switch Control users get longer to reach the Undo control.
            guard pendingDelete != nil else { return }
            let needsMoreTime = UIAccessibility.isVoiceOverRunning
                || UIAccessibility.isSwitchControlRunning
            try? await Task.sleep(for: needsMoreTime ? .seconds(10) : .seconds(4))
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
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        togglePause(subscription)
                    } label: {
                        Label(subscription.isPaused ? "Resume" : "Pause",
                              systemImage: subscription.isPaused ? "play.fill" : "pause.fill")
                    }
                    .tint(subscription.isPaused ? .green : .orange)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        requestDelete(subscription)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                // Swipe actions are invisible to VoiceOver / Switch Control, so the
                // same operations are exposed as custom actions (the Actions rotor).
                .accessibilityAction(named: subscription.isPaused ? "Resume" : "Pause") {
                    togglePause(subscription)
                }
                .accessibilityAction(named: "Delete") {
                    requestDelete(subscription)
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

    /// Opens the Add form, or the paywall when the free tier is full.
    private func requestAdd() {
        if store.canAddSubscription(currentCount: subscriptions.count) {
            isAdding = true
        } else {
            isShowingPaywall = true
        }
    }

    private func requestDelete(_ subscription: Subscription) {
        // Finalize any previous pending delete before starting a new one.
        commitPendingDelete()
        deleteTick += 1
        let name = subscription.name
        withAnimation { pendingDelete = subscription }
        // Share it so the Overview total drops this subscription right away.
        deletionState.pendingID = subscription.persistentModelID
        UIAccessibility.post(
            notification: .announcement,
            argument: "Removed \(name). Undo available."
        )
    }

    private func undoDelete() {
        undoTick += 1
        withAnimation { pendingDelete = nil }
        deletionState.pendingID = nil
    }

    private func commitPendingDelete() {
        guard let target = pendingDelete else { return }
        context.delete(target)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        pendingDelete = nil
        deletionState.pendingID = nil
    }

    private func togglePause(_ subscription: Subscription) {
        pauseTick += 1
        withAnimation {
            subscription.isPaused.toggle()
            if !subscription.isPaused {
                subscription.pausedUntil = nil
            }
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private struct SubscriptionRow: View {
    let subscription: Subscription
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The icon box grows on the same Dynamic Type ramp as its glyph (.title3),
    /// so at large text sizes the symbol can't overflow a fixed 32-pt frame and
    /// collide with the name.
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 32

    var body: some View {
        // Normally the price sits at the trailing edge on one line. At larger
        // text sizes it would squeeze the name, so the row aligns to the top and
        // the price drops onto its own line beneath the name and renewal date.
        let isLarge = dynamicTypeSize >= .xLarge

        HStack(alignment: isLarge ? .top : .center, spacing: DriftSpacing.s12) {
            Image(systemName: subscription.iconName)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(hex: subscription.customColor))
                .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.body)
                statusLine
                if isLarge { amountText }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isLarge { amountText }
        }
        .padding(.vertical, DriftSpacing.s4)
        .opacity(subscription.isPaused ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var statusLine: some View {
        if subscription.isPaused {
            Text("Paused")
                .font(.footnote)
                .foregroundStyle(DriftTheme.subtleText)
        } else {
            Text("Renews \(subscription.nextRenewalDate.formatted(.dateTime.month().day()))")
                .font(.footnote)
                .foregroundStyle(DriftTheme.subtleText)
        }
    }

    private var amountText: some View {
        Text(subscription.monthlyCost,
             format: .currency(code: subscription.currencyCode))
            .font(DriftTypography.amount)
    }

    /// One coherent VoiceOver phrase ("Netflix, $15.99 per month, renews March 3")
    /// instead of four separate stops (icon, name, status, cost).
    private var accessibilityDescription: String {
        let cost = subscription.monthlyCost
            .formatted(.currency(code: subscription.currencyCode))
        let status = subscription.isPaused
            ? "paused"
            : "renews \(subscription.nextRenewalDate.formatted(.dateTime.month(.wide).day()))"
        return "\(subscription.name), \(cost) per month, \(status)"
    }
}
