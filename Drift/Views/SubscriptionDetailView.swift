//
//  SubscriptionDetailView.swift
//  Drift
//
//  The per-subscription detail screen (Part 2 §10.2). Tapping a row in the
//  Subscriptions list pushes this; from here the user can edit, delete, set a
//  one-time cancel reminder, or jump to the matching cancellation guide. Delete
//  routes back through the list so the same Undo affordance applies (no scary
//  confirmation dialog).
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Header icon box scales on the same ramp as its .largeTitle glyph, so the
    /// symbol can't overflow a fixed 56-pt frame (and its background fill) and
    /// collide with the name at large text sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var headerIconSize: CGFloat = 56
    @State private var guideStore = CancellationGuideStore()
    @State private var isEditing = false
    @State private var pauseTick = 0

    // Cancel reminder (a one-time, user-set "remind me to cancel" notification).
    // Seeded from the model in init so toggling/editing fires onChange, but the
    // initial load does not. A reminder whose date has passed reads as "off".
    @State private var cancelReminderOn: Bool
    @State private var cancelReminderDate: Date

    init(subscription: Subscription, onDelete: @escaping (Subscription) -> Void) {
        self.subscription = subscription
        self.onDelete = onDelete
        let future = subscription.cancelReminderDate.flatMap { $0 > Date() ? $0 : nil }
        _cancelReminderOn = State(initialValue: future != nil)
        _cancelReminderDate = State(initialValue: future ?? Self.defaultReminderDate(for: subscription))
    }

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

            Section {
                Toggle("Remind me to cancel", isOn: $cancelReminderOn)
                if cancelReminderOn {
                    DatePicker(
                        "Remind me on",
                        selection: $cancelReminderDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            } header: {
                Text("Cancel reminder")
            } footer: {
                Text("A one-time nudge to cancel this if you're no longer using it. Tapping it opens the cancellation guide.")
            }

            if let guide = matchedGuide {
                Section("Cancel") {
                    NavigationLink {
                        CancellationGuideDetail(guide: guide)
                    } label: {
                        // At large text sizes the label and the friction badge
                        // would fight for width, so the row stacks vertically.
                        let cancelRowLayout = dynamicTypeSize >= .xLarge
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DriftSpacing.s8))
                            : AnyLayout(HStackLayout(spacing: DriftSpacing.s12))
                        cancelRowLayout {
                            Label("How to cancel", systemImage: "scissors")
                                .frame(maxWidth: .infinity, alignment: .leading)
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
        .onChange(of: cancelReminderOn) { _, _ in applyCancelReminder() }
        .onChange(of: cancelReminderDate) { _, _ in applyCancelReminder() }
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

    /// A sensible default: a couple of days before the next renewal, at 10:00,
    /// never in the past.
    private static func defaultReminderDate(for sub: Subscription) -> Date {
        let calendar = Calendar.current
        let twoDaysBefore = calendar.date(byAdding: .day, value: -2, to: sub.nextRenewalDate) ?? sub.nextRenewalDate
        let atTen = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: twoDaysBefore) ?? twoDaysBefore
        return max(atTen, Date().addingTimeInterval(3600))
    }

    /// Persist the chosen reminder (or clear it) and (re)schedule the local notification.
    /// Reads the Sendable fields up front so the model never crosses into the task.
    private func applyCancelReminder() {
        let fireDate = cancelReminderOn ? cancelReminderDate : nil
        subscription.cancelReminderDate = fireDate
        try? context.save()

        let id = subscription.id
        let name = subscription.name
        let monthlyCost = subscription.monthlyCost
        let currencyCode = subscription.currencyCode
        Task {
            await NotificationScheduler.shared.setCancelReminder(
                id: id, name: name, monthlyCost: monthlyCost, currencyCode: currencyCode, fireDate: fireDate
            )
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
                .frame(width: headerIconSize, height: headerIconSize)
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
