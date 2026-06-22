//
//  SubscriptionDetailView.swift
//  Drift
//
//  The per-subscription detail screen (Part 2 §10.2). Tapping a row in the
//  Subscriptions list pushes this; from here the user can edit, delete, or jump
//  to the matching cancellation guide. Delete routes back through the list so
//  the same Undo affordance applies (no scary confirmation dialog).
//

import SwiftData
import SwiftUI
import WidgetKit

struct SubscriptionDetailView: View {
    let subscription: Subscription
    /// Called when the user deletes. The list owns the Undo flow, so a removal
    /// started here can still be taken back once we pop.
    let onDelete: (Subscription) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var guideStore = CancellationGuideStore()
    @State private var isEditing = false
    @State private var pauseTick = 0

    /// What's actually billed each cycle (full cycle price, own currency).
    private var renewalCharge: Decimal {
        subscription.billingCycle.cycleAmount(
            forMonthlyCost: subscription.monthlyCost,
            customCycleDays: subscription.customCycleDays
        )
    }

    /// The bundled cancellation guide for this service: matched by stored
    /// serviceID when present, otherwise by an exact (case-insensitive) name
    /// match so well-known services link up without a manual association yet.
    private var matchedGuide: CancellationGuide? {
        if let serviceID = subscription.serviceID, let guide = guideStore.guide(for: serviceID) {
            return guide
        }
        let name = subscription.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return guideStore.allGuides.first {
            $0.serviceName.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    var body: some View {
        List {
            Section { header }

            Section("Cost") {
                LabeledContent(renewalLabel) {
                    Text(renewalCharge, format: .currency(code: subscription.currencyCode))
                }
                if subscription.billingCycle != .monthly {
                    LabeledContent("Monthly equivalent") {
                        Text(subscription.monthlyCost, format: .currency(code: subscription.currencyCode))
                            .foregroundStyle(DriftTheme.subtleText)
                    }
                }
                LabeledContent("Billing cycle") {
                    Text(subscription.billingCycle.displayName)
                }
            }

            Section("Renewal") {
                LabeledContent("Next renewal") {
                    Text(subscription.nextRenewalDate.formatted(date: .abbreviated, time: .omitted))
                }
                if let category = subscription.category {
                    LabeledContent("Category") { Text(category.name) }
                }
            }

            if let guide = matchedGuide {
                Section("Cancel") {
                    NavigationLink {
                        CancellationGuideDetail(guide: guide)
                    } label: {
                        HStack(spacing: DriftSpacing.s12) {
                            Label("How to cancel", systemImage: "scissors")
                            Spacer(minLength: DriftSpacing.s8)
                            DarkPatternBadge(score: guide.darkPatternScore)
                        }
                    }
                }
            }

            Section {
                Button {
                    togglePause()
                } label: {
                    Label(subscription.isPaused ? "Resume Subscription" : "Pause Subscription",
                          systemImage: subscription.isPaused ? "play.circle" : "pause.circle")
                }
            }

            Section {
                Button(role: .destructive) {
                    onDelete(subscription)
                    dismiss()
                } label: {
                    Label("Delete Subscription", systemImage: "trash")
                }
            }
        }
        .navigationTitle(subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            AddSubscriptionView(existing: subscription)
                .presentationDragIndicator(.visible)
        }
        .driftHaptic(.subscriptionPaused, trigger: pauseTick)
    }

    private var renewalLabel: String {
        switch subscription.billingCycle {
        case .weekly: return "Per week"
        case .monthly: return "Per month"
        case .quarterly: return "Per quarter"
        case .yearly: return "Per year"
        case .custom: return "Per cycle"
        }
    }

    private func togglePause() {
        pauseTick += 1
        subscription.isPaused.toggle()
        if !subscription.isPaused {
            subscription.pausedUntil = nil
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var header: some View {
        HStack(spacing: DriftSpacing.s16) {
            Image(systemName: subscription.iconName)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(hex: subscription.customColor))
                .frame(width: 56, height: 56)
                .background(DriftTheme.neutralFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: DriftSpacing.s4) {
                Text(subscription.name)
                    .font(DriftTypography.sectionTitle)
                    .lineLimit(2)
                if let category = subscription.category {
                    Text(category.name)
                        .font(.footnote)
                        .foregroundStyle(DriftTheme.subtleText)
                }
                if subscription.isPaused {
                    Text("Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DriftSpacing.s8)
    }
}
